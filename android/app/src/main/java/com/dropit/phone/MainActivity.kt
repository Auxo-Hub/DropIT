package com.dropit.phone

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import android.util.Log

/**
 * Minimal setup screen: choose which folders to share, start the storage server, and
 * show whether the Mac has been found and paired. The heavy lifting happens in
 * [StorageBridge] and [StorageHttpServer]; this Activity just surfaces state.
 */
class MainActivity : Activity() {

    private lateinit var storage: StorageBridge
    private lateinit var auth: AuthGate
    private lateinit var server: StorageHttpServer
    private lateinit var link: MacLink

    private lateinit var statusView: TextView
    private lateinit var folderView: TextView
    private lateinit var errorView: TextView

    /** The server and the Mac link both call back synchronously, so the views must
     *  exist before either is started, and callbacks must be ignored until they do. */
    private var uiReady = false
    private var isTornDown = false
    /** False when the storage server could not start; the actions are then disabled
     *  rather than left to dereference an uninitialised bridge. */
    private var startupOk = false
    private val actionButtons = mutableListOf<View>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(buildUi())
        uiReady = true
        render()

        // Everything that can report state is started only once the UI can receive it.
        try {
            storage = StorageBridge(this)
            auth = AuthGate(getSharedPreferences("dropit", MODE_PRIVATE))

            server = StorageHttpServer(storage, auth) {
                onUiThread { render() }
            }
            val port = server.start()
            render()

            link = MacLink(this, auth, { port }) { state -> onUiThread { renderLink(state) } }
            link.start()
            startupOk = true
        } catch (t: Throwable) {
            // A failure here used to be a silent crash. Show it instead.
            Log.e(TAG, "Startup failed", t)
            showFatal(t)
        }
    }

    override fun onDestroy() {
        isTornDown = true
        if (::link.isInitialized) link.stop()
        if (::server.isInitialized) server.stop()
        super.onDestroy()
    }

    /** Posts to the UI thread, ignoring callbacks that arrive after teardown. */
    private fun onUiThread(block: () -> Unit) {
        if (isTornDown) return
        runOnUiThread {
            if (isTornDown || !uiReady) return@runOnUiThread
            block()
        }
    }

    private fun showFatal(t: Throwable) {
        val detail = Log.getStackTraceString(t)
        Log.e(TAG, "Startup failure detail:\n$detail")
        statusView.text = "Could not start the storage server"
        errorView.visibility = View.VISIBLE
        errorView.text = detail
        // The bridge may be only partly built, so make the actions inert.
        actionButtons.forEach { it.isEnabled = false }
    }

    // ------------------------------------------------------------------ ui

    private fun buildUi(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 56, 48, 48)
            setBackgroundColor(0xFF0B0B0F.toInt())
        }

        root.addView(TextView(this).apply {
            text = "Dropit Phone"
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 26f
            setTypeface(typeface, android.graphics.Typeface.BOLD)
        })
        root.addView(TextView(this).apply {
            text = "Share folders from this phone with your Mac over Wi-Fi."
            setTextColor(0xFF8E8E93.toInt())
            textSize = 14f
            setPadding(0, 8, 0, 28)
        })

        statusView = TextView(this).apply {
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 15f
            setPadding(0, 0, 0, 12)
        }
        root.addView(statusView)

        // Startup problems are shown here rather than only in logcat.
        errorView = TextView(this).apply {
            visibility = View.GONE
            setTextColor(0xFFFF453A.toInt())
            textSize = 11f
            setPadding(12, 12, 12, 12)
            setBackgroundColor(0x22FF453A)
            // Use the setter: the SDK exposes isTextSelectable without a matching getter.
            setTextIsSelectable(true)
        }
        root.addView(errorView)

        root.addView(sectionTitle("Shared folders"))
        folderView = TextView(this).apply {
            setTextColor(0xFFBFBFC7.toInt())
            textSize = 14f
        }
        root.addView(folderView)

        actionButtons += button("Share a folder...") { askForFolder() }.apply {
            layoutParams = lp(top = 20)
        }
        root.addView(actionButtons.last())

        val allFiles = button("All-files access: ${if (::storage.isInitialized && storage.hasAllFilesAccess()) "on" else "off"}") {
            if (!::storage.isInitialized) { toast("Storage is not ready"); return@button }
            val intent = storage.allFilesAccessIntent()
            if (intent != null) {
                try { startActivity(intent) } catch (e: Exception) { toast("Open Settings > Apps > Dropit Phone > Permissions") }
            } else {
                toast("All-files access is not needed on this Android version")
            }
        }
        allFiles.layoutParams = lp(top = 10)
        actionButtons += allFiles
        root.addView(allFiles)

        val howTo = sectionTitle("How to use")
        howTo.layoutParams = lp(top = 28)
        root.addView(howTo)
        root.addView(TextView(this).apply {
            text = "Keep this app open while transferring.\n\n" +
                "1. Start a session on your Mac and scan the QR code there.\n" +
                "2. This phone finds the Mac automatically on the same Wi-Fi.\n" +
                "3. On the Mac, open Devices and choose \"Browse storage\" to read, write, " +
                "rename and delete files here.\n\n" +
                "Sharing folders with the folder picker needs no broad storage permission. " +
                "Turning on all-files access lets the Mac reach the rest of internal storage."
            setTextColor(0xFF8E8E93.toInt())
            textSize = 13f
            setLineSpacing(4f, 1.1f)
        })

        return ScrollView(this).apply { addView(root) }
    }

    private fun sectionTitle(text: String) = TextView(this).apply {
        this.text = text
        setTextColor(0xFFFFFFFF.toInt())
        textSize = 16f
        setTypeface(typeface, android.graphics.Typeface.BOLD)
        setPadding(0, 24, 0, 8)
    }

    private fun button(label: String, onClick: () -> Unit) = Button(this).apply {
        text = label
        isAllCaps = false
        setOnClickListener { onClick() }
    }

    private fun lp(top: Int = 0) = LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.WRAP_CONTENT
    ).apply { topMargin = top }

    private fun render() {
        if (!uiReady) return
        val lines = mutableListOf<String>()

        // render() is also called before the server and link are constructed, so every
        // one of these has to be treated as possibly uninitialised.
        val serverUp = ::server.isInitialized && server.port > 0
        lines += if (serverUp) "Storage server running on port ${server.port}" else "Starting the storage server..."
        lines += if (::auth.isInitialized && auth.isPaired()) "Paired with the Mac" else "Waiting for the Mac"
        statusView.text = lines.joinToString("\n")

        if (!::storage.isInitialized) { folderView.text = "Storage is not available."; return }
        val trees = storage.treeLabels()
        folderView.text = if (trees.isEmpty()) {
            "None yet. Tap \"Share a folder...\" to let the Mac browse it."
        } else {
            trees.joinToString("\n") { "• ${it.second}" }
        }
    }

    private fun renderLink(state: MacLink.State) {
        if (!uiReady || isTornDown) return
        val suffix = when (state) {
            is MacLink.State.Searching -> "Looking for your Mac..."
            is MacLink.State.Found -> "Found your Mac, pairing..."
            is MacLink.State.Paired -> "Connected to ${state.name}"
            is MacLink.State.Failed -> state.reason
        }
        val serverUp = ::server.isInitialized && server.port > 0
        statusView.text = (if (serverUp) "Storage server running on port ${server.port}\n" else "") + suffix
    }

    private fun toast(message: String) = Toast.makeText(this, message, Toast.LENGTH_SHORT).show()

    private fun askForFolder() {
        if (!::storage.isInitialized) { toast("Storage is not ready"); return }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
        }
        try {
            startActivityForResult(intent, PICK_FOLDER)
        } catch (e: Exception) {
            toast("This device has no folder picker available")
        }
    }

    @Deprecated("Classic result API keeps the app free of AndroidX dependencies")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_FOLDER) return
        val uri = data?.data ?: return
        if (!::storage.isInitialized) { toast("Storage is not ready"); return }
        val label = uri.lastPathSegment ?: "Folder"
        val ok = storage.addSharedTree(uri, label)
        toast(if (ok) "Shared $label" else "Could not share that folder")
        render()
    }

    companion object {
        private const val PICK_FOLDER = 1001
        private const val TAG = "DropitPhone"
    }
}
