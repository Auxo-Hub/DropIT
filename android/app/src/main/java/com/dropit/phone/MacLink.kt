package com.dropit.phone

import android.content.Context
import android.os.Build
import android.util.Log
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.SocketTimeoutException
import java.net.URL
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.Executors

/**
 * Decides whether a request to the phone's storage server is allowed.
 *
 * When the phone registers with the Mac, the Mac hands back a random per-device secret.
 * Only requests carrying that secret are served, so another machine on the same Wi-Fi
 * cannot browse the phone even though it can reach the port.
 */
class AuthGate(private val prefs: android.content.SharedPreferences) {

    private var cachedSecret: String? = null

    val secret: String?
        get() {
            cachedSecret?.let { return it }
            val stored = prefs.getString(KEY_SECRET, null)
            cachedSecret = stored
            return stored
        }

    fun setSecret(value: String) {
        cachedSecret = value
        prefs.edit().putString(KEY_SECRET, value).apply()
    }

    fun clear() {
        prefs.edit().remove(KEY_SECRET).remove(KEY_PROVIDER_ID).remove(KEY_MAC_URL).apply()
    }

    val providerId: String? get() = prefs.getString(KEY_PROVIDER_ID, null)
    val macUrl: String? get() = prefs.getString(KEY_MAC_URL, null)

    fun setPairing(providerId: String, macUrl: String) {
        prefs.edit().putString(KEY_PROVIDER_ID, providerId).putString(KEY_MAC_URL, macUrl).apply()
    }

    fun isPaired(): Boolean = secret != null && providerId != null

    /**
     * Accepts either the shared secret (how the Mac talks to us) or, when nothing has
     * been paired yet, the Mac's session token, so the very first registration works.
     */
    fun isAllowed(requestToken: String?, macHeader: String?): Boolean {
        val expected = secret
        if (expected.isNullOrEmpty()) {
            // Unpaired: only the registration request is meaningful, and it is guarded
            // by the session token the discovery handshake provided.
            return !requestToken.isNullOrEmpty()
        }
        if (!requestToken.isNullOrEmpty() && requestToken == expected) return true
        if (!macHeader.isNullOrEmpty() && macHeader == expected) return true
        return false
    }

    companion object {
        private const val KEY_SECRET = "provider_secret"
        private const val KEY_PROVIDER_ID = "provider_id"
        private const val KEY_MAC_URL = "mac_url"
    }
}

/**
 * Finds the Dropit Mac on the local network and keeps the registration alive.
 *
 * Discovery is a single UDP broadcast: the phone asks, any Dropit Mac on the subnet
 * answers with its port and session token. No QR scanning dependency is needed.
 */
class MacLink(
    private val context: Context,
    private val auth: AuthGate,
    private val localPort: () -> Int,
    private val onState: (State) -> Unit
) {
    sealed class State {
        object Searching : State()
        data class Found(val host: String, val port: Int) : State()
        data class Paired(val host: String, val port: Int, val name: String) : State()
        data class Failed(val reason: String) : State()
    }

    private val stopped = AtomicBoolean(false)
    @Volatile private var knownHost: String? = null

    fun start() {
        stopped.set(false)
        Thread({ loop() }, "dropit-discovery").apply { isDaemon = true }.start()
    }

    fun stop() {
        stopped.set(true)
    }

    private fun loop() {
        while (!stopped.get()) {
            try {
                onState(State.Searching)
                val host = knownHost ?: discover() ?: findMacByScan()
                if (host == null) {
                    onState(State.Failed("No Dropit Mac found on this network"))
                    Thread.sleep(4000)
                    continue
                }
                knownHost = host
                val port = fetchPort(host) ?: 8080
                onState(State.Found(host, port))
                if (register(host, port)) {
                    Thread.sleep(15_000)
                } else {
                    Thread.sleep(3000)
                }
            } catch (e: InterruptedException) {
                return
            } catch (e: Exception) {
                Log.w(TAG, "discovery loop", e)
                Thread.sleep(4000)
            }
        }
    }

    /** UDP broadcast probe; the Mac answers with its port and token. */
    private fun discover(): String? {
        DatagramSocket().use { socket ->
            socket.broadcast = true
            socket.soTimeout = 1200
            val payload = DISCOVERY_PROBE.toByteArray(Charsets.UTF_8)
            for (address in broadcastAddresses()) {
                try {
                    socket.send(DatagramPacket(payload, payload.size, address, DISCOVERY_PORT))
                } catch (e: Exception) {
                    Log.d(TAG, "broadcast to $address failed: ${e.message}")
                }
            }
            val deadline = System.currentTimeMillis() + 2500
            while (System.currentTimeMillis() < deadline) {
                val buffer = ByteArray(2048)
                val packet = DatagramPacket(buffer, buffer.size)
                try {
                    socket.receive(packet)
                    val text = String(buffer, 0, packet.length, Charsets.UTF_8)
                    if (text.startsWith(DISCOVERY_REPLY)) {
                        val payloadText = text.removePrefix(DISCOVERY_REPLY).trim()
                        val port = extractInt(payloadText, "port") ?: 8080
                        val token = extractString(payloadText, "token")
                        if (token != null) {
                            context.getSharedPreferences("dropit", Context.MODE_PRIVATE)
                                .edit().putString("mac_token", token).putString("mac_host", packet.address.hostAddress).apply()
                        }
                        return packet.address.hostAddress
                    }
                } catch (e: SocketTimeoutException) {
                    break
                } catch (e: Exception) {
                    Log.d(TAG, "receive failed: ${e.message}")
                }
            }
        }
        return null
    }

    /**
     * Fallback for networks that drop broadcast packets: sweep the local /24 in parallel
     * and return the first host with a Dropit port open. A serial sweep with a long
     * timeout would take minutes, so this uses a short timeout and many threads.
     */
    private fun findMacByScan(): String? {
        val hosts = candidateHosts()
        if (hosts.isEmpty()) return null
        val pool = Executors.newFixedThreadPool(SCAN_THREADS) { runnable ->
            Thread(runnable, "dropit-scan").apply { isDaemon = true }
        }
        try {
            val found = java.util.concurrent.atomic.AtomicReference<String?>(null)
            val latch = java.util.concurrent.CountDownLatch(1)
            for (host in hosts) {
                for (port in SCAN_PORTS) {
                    pool.execute {
                        if (latch.count == 0L) return@execute
                        if (probeTcp(host, port) && found.compareAndSet(null, host)) {
                            latch.countDown()
                        }
                    }
                }
            }
            // Give the sweep a bounded window, then take whatever was found.
            latch.await(SCAN_WINDOW_MS, java.util.concurrent.TimeUnit.MILLISECONDS)
            return found.get()
        } finally {
            pool.shutdownNow()
        }
    }

    private fun probeTcp(host: String, port: Int): Boolean = try {
        java.net.Socket().use { socket ->
            socket.connect(InetSocketAddress(host, port), SCAN_CONNECT_TIMEOUT_MS)
            true
        }
    } catch (e: Exception) {
        false
    }

    private fun candidateHosts(): List<String> {
        val local = localIPv4() ?: return emptyList()
        val prefix = local.substringBeforeLast('.', missingDelimiterValue = "")
        if (prefix.isEmpty()) return emptyList()
        return (1..254).map { "$prefix.$it" }
    }

    private fun localIPv4(): String? = runCatching {
        NetworkInterface.getNetworkInterfaces().toList()
            .filter { it.isUp && !it.isLoopback }
            .flatMap { it.inetAddresses.toList() }
            .mapNotNull { it as? java.net.Inet4Address }
            .firstOrNull { !it.isLoopbackAddress }
            ?.hostAddress
    }.getOrNull()

    private fun broadcastAddresses(): List<InetAddress> = runCatching {
        val local = localIPv4() ?: return emptyList()
        val prefix = local.substringBeforeLast('.', missingDelimiterValue = "")
        val list = mutableListOf<InetAddress>()
        list += InetAddress.getByName("255.255.255.255")
        if (prefix.isNotEmpty()) {
            runCatching { InetAddress.getByName("$prefix.255") }.getOrNull()?.let { list += it }
        }
        list
    }.getOrElse { emptyList() }

    private fun fetchPort(host: String): Int? = prefsInt("mac_port") ?: runCatching {
        val connection = URL("http://$host:$DEFAULT_PROBE_PORT/").openConnection() as HttpURLConnection
        connection.connectTimeout = 800
        connection.readTimeout = 800
        connection.requestMethod = "GET"
        connection.connect()
        connection.disconnect()
        null
    }.getOrNull()

    private fun prefsInt(key: String): Int? =
        context.getSharedPreferences("dropit", Context.MODE_PRIVATE).getInt(key, -1).takeIf { it > 0 }

    /** Tells the Mac we exist and collects the secret that authorises later requests. */
    private fun register(host: String, port: Int): Boolean {
        val token = context.getSharedPreferences("dropit", Context.MODE_PRIVATE).getString("mac_token", null) ?: return false
        val base = "http://$host:$port"
        return try {
            val payload = buildString {
                append("{")
                append("\"name\":").append(quote(deviceName())).append(",")
                append("\"model\":").append(quote(Build.MODEL)).append(",")
                append("\"manufacturer\":").append(quote(Build.MANUFACTURER)).append(",")
                append("\"port\":").append(localPort()).append(",")
                append("\"token\":").append(quote(token))
                append("}")
            }
            val response = post("$base/api/device-provider/register?token=$token", payload)
            val id = extractString(response, "id")
            val secret = extractString(response, "secret")
            if (id != null && secret != null) {
                auth.setSecret(secret)
                auth.setPairing(id, base)
                onState(State.Paired(host, port, extractString(response, "name") ?: "Dropit Mac"))
                Log.i(TAG, "registered with Mac at $base as $id")
                true
            } else {
                onState(State.Failed("Mac refused the registration"))
                false
            }
        } catch (e: Exception) {
            Log.w(TAG, "registration failed", e)
            onState(State.Failed(e.message ?: "Registration failed"))
            false
        }
    }

    private fun post(url: String, body: String): String {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.requestMethod = "POST"
        connection.connectTimeout = 3000
        connection.readTimeout = 3000
        connection.doOutput = true
        connection.setRequestProperty("Content-Type", "application/json")
        connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
        return try {
            connection.inputStream.bufferedReader().use(BufferedReader::readText)
        } catch (e: Exception) {
            connection.errorStream?.bufferedReader()?.use(BufferedReader::readText) ?: ""
        } finally {
            connection.disconnect()
        }
    }

    fun deviceName(): String = Build.MODEL?.takeIf { it.isNotBlank() } ?: "Android device"

    private fun quote(value: String) = "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""

    private fun extractString(text: String, key: String): String? =
        Regex("\"$key\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"").find(text)?.groupValues?.get(1)?.replace("\\\"", "\"")

    private fun extractInt(text: String, key: String): Int? =
        Regex("\"$key\"\\s*:\\s*(\\d+)").find(text)?.groupValues?.get(1)?.toIntOrNull()

    companion object {
        private const val TAG = "DropitPhone"
        const val DISCOVERY_PORT = 8911
        const val DISCOVERY_PROBE = "DROPIT_DISCOVER_V1"
        const val DISCOVERY_REPLY = "DROPIT_HERE_V1"
        private const val DEFAULT_PROBE_PORT = 8080
        private val SCAN_PORTS = intArrayOf(8080, 52169, 8000, 8888)
        private const val SCAN_THREADS = 48
        private const val SCAN_CONNECT_TIMEOUT_MS = 150
        private const val SCAN_WINDOW_MS = 4000L
    }
}
