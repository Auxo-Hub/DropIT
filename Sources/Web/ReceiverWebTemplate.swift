import Foundation

public struct ReceiverWebTemplate {
    public struct Context {
        public let sessionToken: String
        public let secureAvailable: Bool
        public let hostNames: [String]

        public init(sessionToken: String, secureAvailable: Bool, hostNames: [String]) {
            self.sessionToken = sessionToken
            self.secureAvailable = secureAvailable
            self.hostNames = hostNames
        }
    }

    public static func html(context: Context? = nil) -> String {
        var page = htmlBody()
        let token = context?.sessionToken ?? ""
        let secure = (context?.secureAvailable ?? false) ? "1" : "0"
        let hosts = (context?.hostNames ?? []).joined(separator: "|")
        page = page
            .replacingOccurrences(of: "__DROPIT_TOKEN__", with: token)
            .replacingOccurrences(of: "__DROPIT_SECURE__", with: secure)
            .replacingOccurrences(of: "__DROPIT_HOSTS__", with: hosts)
        return page
    }

    private static func htmlBody() -> String {
        return """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>Dropit - Local Transfer Hub</title>
    <style>
        :root {
            --bg-color: #000000;
            --card-bg: #0d0d11;
            --card-border: #1c1c22;
            --card-hover: #16161c;
            --text-primary: #ffffff;
            --text-secondary: #8e8e93;
            --accent: #0a84ff;
            --accent-hover: #0071e3;
            --accent-gradient: linear-gradient(135deg, #0a84ff 0%, #5e5ce6 100%);
            --danger: #ff453a;
            --danger-bg: rgba(255, 69, 58, 0.15);
            --danger-border: rgba(255, 69, 58, 0.3);
            --success: #30d158;
            --font: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", "Segoe UI", Roboto, sans-serif;
        }

        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }

        body {
            font-family: var(--font);
            background-color: var(--bg-color);
            color: var(--text-primary);
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            align-items: center;
            padding: 16px;
            -webkit-font-smoothing: antialiased;
        }

        .header {
            width: 100%;
            max-width: 520px;
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 12px 4px 18px;
            gap: 8px;
        }

        .brand {
            display: flex;
            align-items: center;
            gap: 10px;
            font-size: 18px;
            font-weight: 700;
            letter-spacing: -0.3px;
        }

        .brand-icon {
            width: 32px;
            height: 32px;
            background: var(--accent-gradient);
            border-radius: 9px;
            display: flex;
            align-items: center;
            justify-content: center;
            box-shadow: 0 4px 12px rgba(10, 132, 255, 0.35);
        }

        .brand-icon svg {
            width: 18px;
            height: 18px;
            fill: none;
            stroke: #fff;
            stroke-width: 2.2;
        }

        .header-actions {
            display: flex;
            align-items: center;
            gap: 8px;
        }

        .btn-header {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            background: var(--card-bg);
            border: 1px solid var(--card-border);
            color: var(--text-primary);
            padding: 6px 12px;
            border-radius: 14px;
            font-size: 12px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.15s;
            -webkit-tap-highlight-color: transparent;
        }

        .btn-header:hover {
            background: var(--card-hover);
            border-color: rgba(255, 255, 255, 0.2);
        }

        .btn-disconnect {
            background: var(--danger-bg);
            border-color: var(--danger-border);
            color: var(--danger);
        }

        .btn-disconnect:hover {
            background: rgba(255, 69, 58, 0.25);
            border-color: var(--danger);
        }

        .status-dot {
            width: 7px;
            height: 7px;
            background-color: var(--success);
            border-radius: 50%;
            box-shadow: 0 0 6px var(--success);
            animation: pulse 2s infinite;
        }

        @keyframes pulse {
            0%, 100% { opacity: 1; transform: scale(1); }
            50% { opacity: 0.5; transform: scale(0.85); }
        }

        /* Tabs */
        .tabs-container {
            width: 100%;
            max-width: 520px;
            display: flex;
            background: #08080a;
            border: 1px solid var(--card-border);
            border-radius: 16px;
            padding: 4px;
            margin-bottom: 18px;
            gap: 4px;
        }

        .tab-btn {
            flex: 1;
            padding: 9px 8px;
            background: transparent;
            border: none;
            border-radius: 12px;
            color: var(--text-secondary);
            font-size: 13px;
            font-weight: 600;
            cursor: pointer;
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 6px;
            transition: all 0.2s;
            -webkit-tap-highlight-color: transparent;
        }

        .tab-btn.active {
            background: var(--card-bg);
            color: var(--text-primary);
            border: 1px solid var(--card-border);
            box-shadow: 0 2px 8px rgba(0, 0, 0, 0.5);
        }

        .badge-count {
            background: var(--accent);
            color: #fff;
            padding: 2px 6px;
            border-radius: 10px;
            font-size: 10px;
            font-weight: 700;
        }

        /* Main Container */
        .main-card {
            width: 100%;
            max-width: 520px;
            background: var(--card-bg);
            border: 1px solid var(--card-border);
            border-radius: 24px;
            padding: 20px 16px;
            box-shadow: 0 20px 40px -10px rgba(0, 0, 0, 0.8);
        }

        .section-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            margin-bottom: 16px;
        }

        .section-title {
            font-size: 15px;
            font-weight: 700;
            letter-spacing: -0.2px;
        }

        .btn-download-all {
            background: var(--accent);
            border: none;
            color: #fff;
            padding: 7px 13px;
            border-radius: 12px;
            font-size: 12px;
            font-weight: 600;
            cursor: pointer;
            display: flex;
            align-items: center;
            gap: 6px;
            box-shadow: 0 4px 12px rgba(10, 132, 255, 0.3);
        }

        /* File List */
        .file-list {
            display: flex;
            flex-direction: column;
            gap: 9px;
        }

        .file-item {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 12px 14px;
            background: #08080b;
            border: 1px solid var(--card-border);
            border-radius: 16px;
            transition: all 0.2s;
        }

        .file-info {
            display: flex;
            align-items: center;
            gap: 12px;
            min-width: 0;
            flex: 1;
            margin-right: 10px;
        }

        .file-icon {
            width: 38px;
            height: 38px;
            background: rgba(10, 132, 255, 0.12);
            border-radius: 11px;
            display: flex;
            align-items: center;
            justify-content: center;
            flex-shrink: 0;
            color: var(--accent);
        }

        .file-details {
            min-width: 0;
            flex: 1;
        }

        .file-name {
            font-size: 14px;
            font-weight: 600;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }

        .file-size {
            font-size: 12px;
            color: var(--text-secondary);
            margin-top: 2px;
        }

        .btn-file-dl {
            background: rgba(255, 255, 255, 0.08);
            border: 1px solid rgba(255, 255, 255, 0.1);
            color: var(--text-primary);
            padding: 7px 12px;
            border-radius: 11px;
            font-size: 12px;
            font-weight: 600;
            cursor: pointer;
            display: flex;
            align-items: center;
            gap: 5px;
            flex-shrink: 0;
            transition: all 0.15s;
            text-decoration: none;
        }

        .btn-file-dl:hover {
            background: rgba(255, 255, 255, 0.15);
        }

        .empty-state {
            padding: 40px 20px;
            text-align: center;
        }

        .empty-radar {
            width: 58px;
            height: 58px;
            margin: 0 auto 14px;
            background: rgba(10, 132, 255, 0.1);
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            color: var(--accent);
            animation: pulse 2.5s infinite;
        }

        .empty-title {
            font-size: 14px;
            font-weight: 600;
            margin-bottom: 6px;
        }

        .empty-desc {
            font-size: 12px;
            color: var(--text-secondary);
        }

        /* Upload Section */
        .upload-drop-zone {
            border: 2px dashed rgba(255, 255, 255, 0.16);
            border-radius: 18px;
            padding: 30px 16px;
            text-align: center;
            cursor: pointer;
            transition: all 0.2s;
            background: #08080b;
        }

        .upload-drop-zone:hover, .upload-drop-zone.dragover {
            border-color: var(--accent);
            background: rgba(10, 132, 255, 0.06);
        }

        .upload-icon {
            width: 50px;
            height: 50px;
            margin: 0 auto 12px;
            background: var(--accent-gradient);
            border-radius: 15px;
            display: flex;
            align-items: center;
            justify-content: center;
            box-shadow: 0 6px 18px rgba(10, 132, 255, 0.3);
        }

        .upload-icon svg {
            width: 24px;
            height: 24px;
            fill: none;
            stroke: #fff;
            stroke-width: 2.2;
        }

        .staged-list {
            margin-top: 14px;
            display: flex;
            flex-direction: column;
            gap: 8px;
            max-height: 220px;
            overflow-y: auto;
        }

        .staged-item {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 10px 12px;
            background: #08080b;
            border: 1px solid var(--card-border);
            border-radius: 12px;
            font-size: 13px;
        }

        .staged-name {
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
            max-width: 260px;
        }

        .btn-upload-submit {
            width: 100%;
            margin-top: 14px;
            background: var(--accent-gradient);
            border: none;
            color: #fff;
            padding: 13px;
            border-radius: 14px;
            font-size: 14px;
            font-weight: 700;
            cursor: pointer;
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 8px;
            box-shadow: 0 4px 16px rgba(10, 132, 255, 0.35);
        }

        .btn-upload-submit:disabled {
            opacity: 0.6;
            cursor: not-allowed;
        }

        /* Progress Bar */
        .progress-card {
            margin-top: 16px;
            background: #08080b;
            border: 1px solid var(--card-border);
            border-radius: 16px;
            padding: 14px;
            display: none;
        }

        .progress-card.active {
            display: block;
        }

        .progress-bar-bg {
            width: 100%;
            height: 7px;
            background: rgba(255, 255, 255, 0.08);
            border-radius: 10px;
            overflow: hidden;
            margin: 8px 0;
        }

        .progress-bar-fill {
            height: 100%;
            width: 0%;
            background: var(--accent-gradient);
            border-radius: 10px;
            transition: width 0.15s ease;
        }

        .progress-stats {
            display: flex;
            justify-content: space-between;
            font-size: 11px;
            color: var(--text-secondary);
        }

        /* History Tab */
        .history-list {
            display: flex;
            flex-direction: column;
            gap: 8px;
        }

        .history-item {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 10px 12px;
            background: #08080b;
            border: 1px solid var(--card-border);
            border-radius: 14px;
        }

        .history-badge {
            font-size: 10px;
            font-weight: 700;
            padding: 3px 8px;
            border-radius: 8px;
            text-transform: uppercase;
        }

        .badge-sent {
            background: rgba(10, 132, 255, 0.15);
            color: #58a6ff;
            border: 1px solid rgba(10, 132, 255, 0.3);
        }

        .badge-received {
            background: rgba(48, 209, 88, 0.15);
            color: #30d158;
            border: 1px solid rgba(48, 209, 88, 0.3);
        }

        /* Browse Mac storage */
        .btn-mini {
            background: rgba(255, 255, 255, 0.08);
            border: 1px solid rgba(255, 255, 255, 0.12);
            color: var(--text-primary);
            padding: 5px 10px;
            border-radius: 9px;
            font-size: 11px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.15s;
        }

        .btn-mini:hover { background: rgba(255, 255, 255, 0.16); }

        .fs-crumbs {
            display: flex;
            align-items: center;
            flex-wrap: wrap;
            gap: 4px;
            font-size: 12px;
            color: var(--text-secondary);
            margin-bottom: 10px;
            padding: 8px 10px;
            background: #08080b;
            border: 1px solid var(--card-border);
            border-radius: 12px;
        }

        .fs-crumb {
            cursor: pointer;
            padding: 2px 5px;
            border-radius: 6px;
            font-weight: 600;
        }

        .fs-crumb:hover { background: rgba(10, 132, 255, 0.2); color: #fff; }
        .fs-crumb.current { color: var(--text-primary); }

        .fs-list {
            display: flex;
            flex-direction: column;
            gap: 7px;
            max-height: 52vh;
            overflow-y: auto;
        }

        .fs-item {
            display: flex;
            align-items: center;
            gap: 10px;
            padding: 10px 12px;
            background: #08080b;
            border: 1px solid var(--card-border);
            border-radius: 13px;
        }

        .fs-item.clickable { cursor: pointer; }
        .fs-item.clickable:hover { background: var(--card-hover); border-color: rgba(10, 132, 255, 0.4); }

        .fs-icon {
            width: 32px;
            height: 32px;
            border-radius: 9px;
            display: flex;
            align-items: center;
            justify-content: center;
            flex-shrink: 0;
            background: rgba(10, 132, 255, 0.12);
            color: var(--accent);
        }

        .fs-icon.folder { background: rgba(94, 92, 230, 0.16); color: #8e8cf0; }

        .fs-name {
            font-size: 13px;
            font-weight: 600;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
            flex: 1;
            min-width: 0;
        }

        .fs-meta { font-size: 11px; color: var(--text-secondary); margin-top: 2px; }

        .fs-actions { display: flex; gap: 6px; flex-shrink: 0; }

        .fs-act {
            background: rgba(255, 255, 255, 0.08);
            border: 1px solid rgba(255, 255, 255, 0.1);
            color: var(--text-primary);
            border-radius: 9px;
            padding: 5px 9px;
            font-size: 11px;
            font-weight: 600;
            cursor: pointer;
        }

        .fs-act:hover { background: rgba(255, 255, 255, 0.16); }
        .fs-act.danger { color: var(--danger); background: var(--danger-bg); border-color: var(--danger-border); }

        .fs-empty { padding: 34px 20px; text-align: center; }
        .fs-error {
            margin-top: 10px;
            padding: 10px 12px;
            border-radius: 11px;
            background: var(--danger-bg);
            border: 1px solid var(--danger-border);
            color: var(--danger);
            font-size: 12px;
            font-weight: 600;
        }

        .fs-hint {
            margin-top: 12px;
            font-size: 11px;
            color: var(--text-secondary);
            line-height: 1.5;
            text-align: center;
        }

        .modal-input {
            width: 100%;
            background: #08080b;
            border: 1px solid var(--card-border);
            border-radius: 12px;
            color: #fff;
            padding: 11px 13px;
            font-size: 14px;
            outline: none;
        }

        .modal-input:focus { border-color: var(--accent); }

        /* Modal Overlay */
        .modal-overlay {
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: rgba(0, 0, 0, 0.85);
            backdrop-filter: blur(12px);
            -webkit-backdrop-filter: blur(12px);
            display: none;
            align-items: center;
            justify-content: center;
            padding: 16px;
            z-index: 100;
        }

        .modal-overlay.open {
            display: flex;
        }

        .modal-card {
            width: 100%;
            max-width: 440px;
            background: #0d0d11;
            border: 1px solid var(--card-border);
            border-radius: 22px;
            padding: 20px;
            box-shadow: 0 24px 48px rgba(0, 0, 0, 0.9);
        }

        .modal-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            margin-bottom: 16px;
        }

        .modal-title {
            font-size: 16px;
            font-weight: 700;
        }

        .btn-modal-close {
            background: rgba(255, 255, 255, 0.08);
            border: none;
            color: #fff;
            width: 28px;
            height: 28px;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            cursor: pointer;
        }

        .device-item {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 12px;
            background: #08080b;
            border: 1px solid var(--card-border);
            border-radius: 14px;
            margin-bottom: 8px;
            transition: all 0.15s ease;
        }

        .device-item.clickable:hover {
            background: var(--card-hover);
            border-color: rgba(10, 132, 255, 0.4);
        }

        .device-info-left {
            display: flex;
            align-items: center;
            gap: 10px;
            flex: 1;
            min-width: 0;
        }

        .device-icon-box {
            width: 36px;
            height: 36px;
            background: rgba(255, 255, 255, 0.08);
            border-radius: 10px;
            display: flex;
            align-items: center;
            justify-content: center;
            color: var(--accent);
            flex-shrink: 0;
        }

        .btn-device-send {
            background: var(--accent);
            border: none;
            color: #ffffff;
            padding: 6px 12px;
            border-radius: 10px;
            font-size: 11px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.15s;
            display: inline-flex;
            align-items: center;
            gap: 5px;
            white-space: nowrap;
        }

        .btn-device-send:hover {
            background: var(--accent-hover);
            transform: scale(1.02);
        }

        .target-device-banner {
            display: flex;
            align-items: center;
            justify-content: space-between;
            background: rgba(10, 132, 255, 0.12);
            border: 1px solid rgba(10, 132, 255, 0.35);
            border-radius: 14px;
            padding: 10px 14px;
            margin-bottom: 14px;
            animation: fadeIn 0.2s ease;
        }

        .target-device-info {
            display: flex;
            align-items: center;
            gap: 8px;
            min-width: 0;
        }

        .target-badge {
            font-size: 10px;
            font-weight: 700;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            background: var(--accent);
            color: #fff;
            padding: 2px 7px;
            border-radius: 6px;
            flex-shrink: 0;
        }

        .target-name {
            font-weight: 600;
            font-size: 13px;
            color: #fff;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }

        .btn-clear-target {
            background: rgba(255, 255, 255, 0.1);
            border: none;
            color: var(--text-secondary);
            font-size: 11px;
            font-weight: 600;
            padding: 5px 9px;
            border-radius: 8px;
            cursor: pointer;
            transition: all 0.15s;
            flex-shrink: 0;
        }

        .btn-clear-target:hover {
            background: rgba(255, 255, 255, 0.2);
            color: #fff;
        }

        .badge-targeted {
            display: inline-block;
            font-size: 10px;
            font-weight: 700;
            color: #5e5ce6;
            background: rgba(94, 92, 230, 0.2);
            border: 1px solid rgba(94, 92, 230, 0.35);
            padding: 1px 6px;
            border-radius: 6px;
            margin-left: 6px;
            vertical-align: middle;
        }

        /* Disconnected State Screen */
        .disconnected-screen {
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: #000000;
            display: none;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            padding: 24px;
            text-align: center;
            z-index: 200;
        }

        .disconnected-screen.show {
            display: flex;
        }

        .disconnected-icon {
            width: 72px;
            height: 72px;
            background: var(--danger-bg);
            border: 1px solid var(--danger-border);
            border-radius: 24px;
            display: flex;
            align-items: center;
            justify-content: center;
            color: var(--danger);
            margin-bottom: 18px;
        }

        .toast {
            position: fixed;
            bottom: 24px;
            background: #1c1c22;
            border: 1px solid rgba(255, 255, 255, 0.15);
            color: #fff;
            padding: 10px 18px;
            border-radius: 20px;
            font-size: 13px;
            font-weight: 600;
            box-shadow: 0 10px 30px rgba(0, 0, 0, 0.8);
            opacity: 0;
            transform: translateY(20px);
            transition: all 0.3s;
            pointer-events: none;
            z-index: 300;
        }

        .toast.show {
            opacity: 1;
            transform: translateY(0);
        }
    </style>
</head>
<body>
    <!-- Header -->
    <div class="header">
        <div class="brand">
            <div class="brand-icon">
                <svg viewBox="0 0 24 24">
                    <path d="M12 2v14M5 9l7 7 7-7"></path>
                    <path d="M20 21H4"></path>
                </svg>
            </div>
            <span>Dropit</span>
        </div>

        <div class="header-actions">
            <button class="btn-header" onclick="openDevicesModal()">
                <div class="status-dot"></div>
                <span id="headerDevicesText">Devices</span>
            </button>
            <button class="btn-header btn-disconnect" onclick="disconnectSelf()">
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
                    <path d="M18.36 6.64a9 9 0 1 1-12.73 0"></path>
                    <line x1="12" y1="2" x2="12" y2="12"></line>
                </svg>
                <span>Disconnect</span>
            </button>
        </div>
    </div>

    <!-- Navigation Tabs -->
    <div class="tabs-container">
        <button id="tabReceive" class="tab-btn active" onclick="switchTab('receive')">
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2">
                <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path>
                <polyline points="7 10 12 15 17 10"></polyline>
                <line x1="12" y1="15" x2="12" y2="3"></line>
            </svg>
            <span>From Mac</span>
            <span id="sharedCountBadge" class="badge-count" style="display:none">0</span>
        </button>
        <button id="tabSend" class="tab-btn" onclick="switchTab('send')">
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2">
                <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path>
                <polyline points="17 8 12 3 7 8"></polyline>
                <line x1="12" y1="3" x2="12" y2="15"></line>
            </svg>
            <span>Send to Mac</span>
        </button>
        <button id="tabHistory" class="tab-btn" onclick="switchTab('history')">
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2">
                <circle cx="12" cy="12" r="10"></circle>
                <polyline points="12 6 12 12 16 14"></polyline>
            </svg>
            <span>History</span>
        </button>
        <button id="tabBrowse" class="tab-btn" onclick="switchTab('browse')">
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2">
                <path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"></path>
            </svg>
            <span>Browse Mac</span>
        </button>
    </div>

    <!-- Main Card Content -->
    <div class="main-card">
        <!-- Tab 1: From Mac -->
        <div id="receiveSection">
            <div class="section-header">
                <div class="section-title">Files Shared by Mac</div>
                <button id="btnDownloadAll" class="btn-download-all" style="display:none" onclick="downloadAllFiles()">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
                        <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path>
                        <polyline points="7 10 12 15 17 10"></polyline>
                        <line x1="12" y1="15" x2="12" y2="3"></line>
                    </svg>
                    <span>Download All</span>
                </button>
            </div>

            <div id="fileList" class="file-list"></div>

            <div id="emptyFiles" class="empty-state">
                <div class="empty-radar">
                    <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                        <path d="M12 2v20M2 12h20"></path>
                        <circle cx="12" cy="12" r="9"></circle>
                    </svg>
                </div>
                <div class="empty-title">Waiting for files from Mac...</div>
                <div class="empty-desc">When the sender drops files on Mac, they will instantly appear here.</div>
            </div>

            <!-- Download Progress Bar -->
            <div id="dlProgressCard" class="progress-card">
                <div style="font-size:13px; font-weight:600;" id="dlFileName">Downloading...</div>
                <div class="progress-bar-bg">
                    <div id="dlProgressBar" class="progress-bar-fill"></div>
                </div>
                <div class="progress-stats">
                    <span id="dlSpeed">0 MB/s</span>
                    <span id="dlPercent">0%</span>
                </div>
            </div>
        </div>

        <!-- Tab 2: Send to Mac -->
        <div id="sendSection" style="display:none">
            <div class="section-header">
                <div class="section-title" id="sendSectionTitle">Upload to Mac</div>
            </div>

            <!-- Target Device Banner (for device-to-device transfer) -->
            <div id="targetDeviceBanner" class="target-device-banner" style="display:none;">
                <div class="target-device-info">
                    <span class="target-badge">Sending to</span>
                    <span id="targetDeviceNameText" class="target-name">Target Device</span>
                </div>
                <button class="btn-clear-target" onclick="clearTargetDevice()">✕ Send to Mac instead</button>
            </div>

            <input id="fileInput" type="file" multiple style="display:none" onchange="handleFileSelect(event)">

            <div class="upload-drop-zone" id="dropZone" onclick="document.getElementById('fileInput').click()">
                <div class="upload-icon">
                    <svg viewBox="0 0 24 24">
                        <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path>
                        <polyline points="17 8 12 3 7 8"></polyline>
                        <line x1="12" y1="3" x2="12" y2="15"></line>
                    </svg>
                </div>
                <div style="font-size:15px; font-weight:600; margin-bottom:4px;">Tap to Select Files</div>
                <div style="font-size:12px; color:var(--text-secondary);">Photos, videos, or documents from device</div>
            </div>

            <div id="stagedList" class="staged-list"></div>

            <button id="btnUpload" class="btn-upload-submit" style="display:none" onclick="startUpload()">
                <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
                    <line x1="12" y1="19" x2="12" y2="5"></line>
                    <polyline points="5 12 12 5 19 12"></polyline>
                </svg>
                <span id="btnUploadText">Send to Mac</span>
            </button>

            <!-- Upload Progress Bar -->
            <div id="upProgressCard" class="progress-card">
                <div style="font-size:13px; font-weight:600;" id="upFileName">Sending...</div>
                <div class="progress-bar-bg">
                    <div id="upProgressBar" class="progress-bar-fill"></div>
                </div>
                <div class="progress-stats">
                    <span id="upSpeed">0 MB/s</span>
                    <span id="upPercent">0%</span>
                </div>
            </div>
        </div>

        <!-- Tab 3: History -->
        <div id="historySection" style="display:none">
            <div class="section-header">
                <div class="section-title">Transfer History</div>
            </div>
            <div id="historyList" class="history-list"></div>
            <div id="emptyHistory" class="empty-state">
                <div class="empty-title">No transfers yet</div>
                <div class="empty-desc">Transferred files will appear here.</div>
            </div>
        </div>

        <!-- Tab 4: Browse Mac storage -->
        <div id="browseSection" style="display:none">
            <div class="section-header">
                <div class="section-title">Mac Folders</div>
                <div style="display:flex; gap:6px;">
                    <button class="btn-mini" onclick="fsNewFolder()">+ Folder</button>
                    <button class="btn-mini" onclick="fsRefresh()">Refresh</button>
                </div>
            </div>

            <div class="fs-crumbs" id="fsCrumbs"></div>
            <div class="fs-list" id="fsList"></div>
            <div class="fs-empty" id="fsEmpty" style="display:none">
                <div class="empty-title">This folder is empty</div>
                <div class="empty-desc">Use + Folder to create something here.</div>
            </div>
            <div class="fs-error" id="fsError" style="display:none;"></div>

            <div class="fs-hint" id="fsHint"></div>
        </div>
    </div>

    <!-- Connected Devices Modal -->
    <div id="devicesModal" class="modal-overlay" onclick="if(event.target===this) closeDevicesModal()">
        <div class="modal-card">
            <div class="modal-header">
                <div class="modal-title">Connected Devices</div>
                <button class="btn-modal-close" onclick="closeDevicesModal()">✕</button>
            </div>
            <div id="modalDeviceList"></div>
        </div>
    </div>

    <!-- New Folder Modal -->
    <div id="folderModal" class="modal-overlay" onclick="if(event.target===this) closeFolderModal()">
        <div class="modal-card">
            <div class="modal-header">
                <div class="modal-title">New Folder</div>
                <button class="btn-modal-close" onclick="closeFolderModal()">✕</button>
            </div>
            <input id="folderNameInput" class="modal-input" type="text" placeholder="Folder name" maxlength="120">
            <div style="display:flex; gap:8px; margin-top:14px;">
                <button class="btn-mini" style="flex:1; padding:11px;" onclick="closeFolderModal()">Cancel</button>
                <button class="btn-upload-submit" style="margin-top:0; padding:11px;" onclick="confirmNewFolder()">Create</button>
            </div>
        </div>
    </div>

    <!-- Disconnected Screen -->
    <div id="disconnectedScreen" class="disconnected-screen">
        <div class="disconnected-icon">
            <svg width="34" height="34" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M18.36 6.64a9 9 0 1 1-12.73 0"></path>
                <line x1="12" y1="2" x2="12" y2="12"></line>
            </svg>
        </div>
        <h2 style="font-size:20px; font-weight:700; margin-bottom:8px;">Disconnected</h2>
        <p style="font-size:14px; color:var(--text-secondary); max-width:300px; margin-bottom:24px;">
            You have disconnected or were disconnected by the host Mac.
        </p>
        <button class="btn-upload-submit" style="width:auto; padding:12px 28px;" onclick="reconnectSelf()">
            Reconnect
        </button>
    </div>

    <div id="toast" class="toast"></div>

    <script>
        // Device Identification
        const SESSION_TOKEN = new URLSearchParams(window.location.search).get('token') || '';

        // Attach the pairing token to every same-origin request so the host can tell a
        // freshly scanned code apart from one the user already refreshed.
        (function () {
            const nativeFetch = window.fetch.bind(window);
            window.fetch = function (input, init) {
                try {
                    const url = new URL(typeof input === 'string' ? input : input.url, window.location.href);
                    if (SESSION_TOKEN && url.origin === window.location.origin && !url.searchParams.has('token')) {
                        url.searchParams.set('token', SESSION_TOKEN);
                    }
                    return nativeFetch(url.toString(), init);
                } catch (e) {
                    return nativeFetch(input, init);
                }
            };
        })();

        function getDeviceId() {
            let id = localStorage.getItem('dropit_device_id');
            if (!id) {
                id = 'dev_' + Math.random().toString(36).substring(2, 10) + Date.now().toString(36);
                localStorage.setItem('dropit_device_id', id);
            }
            return id;
        }

        function getDeviceName() {
            const ua = navigator.userAgent;
            if (/iPad|Tablet/i.test(ua)) return 'iPad';
            if (/iPhone/i.test(ua)) return 'iPhone';
            if (/Android/i.test(ua)) return 'Android Device';
            if (/Macintosh/i.test(ua)) return 'Mac Computer';
            if (/Windows/i.test(ua)) return 'Windows PC';
            if (/Linux/i.test(ua)) return 'Linux Device';
            return 'Mobile Device';
        }

        const myDeviceId = getDeviceId();
        const myDeviceName = getDeviceName();

        let currentSharedFiles = [];
        let stagedFiles = [];
        let isTransferring = false;
        let isDisconnected = false;

        // Register device on startup
        async function registerDevice() {
            try {
                const res = await fetch('/api/register-device', {
                    method: 'POST',
                    headers: {
                        'x-device-id': myDeviceId,
                        'x-device-name': encodeURIComponent(myDeviceName)
                    }
                });
                const data = await res.json();
                if (data.isBlocked) {
                    showDisconnectedState();
                }
            } catch (e) {}
        }
        registerDevice();

        // Tab Switching
        function switchTab(tab) {
            document.getElementById('tabReceive').classList.toggle('active', tab === 'receive');
            document.getElementById('tabSend').classList.toggle('active', tab === 'send');
            document.getElementById('tabHistory').classList.toggle('active', tab === 'history');
            document.getElementById('tabBrowse').classList.toggle('active', tab === 'browse');
            document.getElementById('receiveSection').style.display = tab === 'receive' ? 'block' : 'none';
            document.getElementById('sendSection').style.display = tab === 'send' ? 'block' : 'none';
            document.getElementById('historySection').style.display = tab === 'history' ? 'block' : 'none';
            document.getElementById('browseSection').style.display = tab === 'browse' ? 'block' : 'none';

            if (tab === 'history') {
                loadHistory();
            } else if (tab === 'browse') {
                if (currentFsPath === null) fsOpen('');
                else fsRefresh();
            }
        }

        function showToast(msg) {
            const t = document.getElementById('toast');
            t.innerText = msg;
            t.classList.add('show');
            setTimeout(() => t.classList.remove('show'), 3000);
        }

        // Live Sync Polling
        async function syncFiles() {
            if (isDisconnected) return;
            try {
                const res = await fetch('/api/sync', {
                    headers: {
                        'x-device-id': myDeviceId,
                        'x-device-name': encodeURIComponent(myDeviceName)
                    }
                });
                if (!res.ok) return;
                const data = await res.json();
                if (data.disconnected) {
                    showDisconnectedState();
                    return;
                }
                renderFiles(data.files || []);
            } catch (e) {}
        }
        setInterval(syncFiles, 1500);
        syncFiles();

        // Poll Connected Devices
        async function updateDevicesBadge() {
            if (isDisconnected) return;
            try {
                const res = await fetch('/api/devices', {
                    headers: { 'x-device-id': myDeviceId }
                });
                if (!res.ok) return;
                const data = await res.json();
                const devices = (data.devices || []).filter(d => !d.isBlocked);
                document.getElementById('headerDevicesText').innerText = `${devices.length} Device${devices.length > 1 ? 's' : ''}`;
            } catch (e) {}
        }
        setInterval(updateDevicesBadge, 3000);
        updateDevicesBadge();

        function renderFiles(files) {
            currentSharedFiles = files;
            const list = document.getElementById('fileList');
            const empty = document.getElementById('emptyFiles');
            const dlAllBtn = document.getElementById('btnDownloadAll');
            const countBadge = document.getElementById('sharedCountBadge');

            if (files.length > 0) {
                countBadge.innerText = files.length;
                countBadge.style.display = 'inline-block';
                dlAllBtn.style.display = 'flex';
                empty.style.display = 'none';
            } else {
                countBadge.style.display = 'none';
                dlAllBtn.style.display = 'none';
                empty.style.display = 'block';
            }

            list.innerHTML = files.map(f => {
                const fromPeer = f.senderDeviceId && f.senderDeviceId !== 'host_mac' && f.senderDeviceId !== myDeviceId;
                const senderLabel = fromPeer ? `From ${f.senderDeviceName || 'Peer'}` : '';
                const isForMe = f.isForMe;
                return `
                <div class="file-item">
                    <div class="file-info">
                        <div class="file-icon">
                            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                <path d="M13 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"></path>
                                <polyline points="13 2 13 9 20 9"></polyline>
                            </svg>
                        </div>
                        <div class="file-details">
                            <div class="file-name" title="${f.name}">
                                ${f.name}
                                ${isForMe ? '<span class="badge-targeted">For You</span>' : ''}
                            </div>
                            <div class="file-size">
                                ${f.formattedSize}
                                ${senderLabel ? ` • <span style="color:var(--accent); font-weight:600;">${senderLabel}</span>` : ''}
                            </div>
                        </div>
                    </div>
                    <button class="btn-file-dl" onclick="downloadSingleFile('${f.id}', '${encodeURIComponent(f.name)}')">
                        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
                            <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path>
                            <polyline points="7 10 12 15 17 10"></polyline>
                            <line x1="12" y1="15" x2="12" y2="3"></line>
                        </svg>
                        <span>Download</span>
                    </button>
                </div>
            `;
            }).join('');
        }

        // File Downloads
        async function downloadSingleFile(fileId, fileName) {
            const decodedName = decodeURIComponent(fileName);
            const progressCard = document.getElementById('dlProgressCard');
            const progressBar = document.getElementById('dlProgressBar');
            const percentText = document.getElementById('dlPercent');
            const speedText = document.getElementById('dlSpeed');
            const nameText = document.getElementById('dlFileName');

            progressCard.classList.add('active');
            nameText.innerText = 'Downloading ' + decodedName + '...';
            progressBar.style.width = '0%';

            // Resume: remember how many bytes of this file we already stored.
            const resumeKey = 'dropit_dl_' + fileId;
            let already = parseInt(localStorage.getItem(resumeKey) || '0', 10) || 0;
            const chunks = [];
            if (already > 0) {
                const cached = await readCachedChunk(fileId);
                if (cached && cached.length >= already) {
                    chunks.push(cached.slice(0, already));
                } else {
                    already = 0;
                    localStorage.removeItem(resumeKey);
                }
            }

            try {
                const headers = {
                    'x-device-id': myDeviceId,
                    'x-device-name': encodeURIComponent(myDeviceName)
                };
                if (already > 0) headers['Range'] = 'bytes=' + already + '-';

                const res = await fetch('/download/' + fileId + '?deviceId=' + myDeviceId, { headers: headers });
                if (!res.ok) throw new Error('Download failed');

                const total = parseInt(res.headers.get('content-length') || '0', 10) + already;
                if (!res.body || typeof res.body.getReader !== 'function') {
                    window.location.href = '/download/' + fileId + '?deviceId=' + myDeviceId;
                    progressCard.classList.remove('active');
                    return;
                }

                const reader = res.body.getReader();
                let received = already;
                let lastTime = Date.now();
                let lastBytes = already;
                if (res.status === 206) showToast('Resuming from ' + formatBytes(already));

                let saveTimer = null;
                while (true) {
                    const { done, value } = await reader.read();
                    if (done) break;
                    chunks.push(value);
                    received += value.length;
                    localStorage.setItem(resumeKey, String(received));

                    const now = Date.now();
                    const percent = total > 0 ? Math.min(100, Math.round((received / total) * 100)) : 50;
                    progressBar.style.width = percent + '%';
                    percentText.innerText = percent + '%';

                    if (now - lastTime >= 250) {
                        const elapsed = (now - lastTime) / 1000;
                        const speed = (received - lastBytes) / elapsed;
                        speedText.innerText = formatSpeed(speed);
                        lastTime = now;
                        lastBytes = received;
                    }

                    if (!saveTimer) {
                        saveTimer = setTimeout(() => { saveTimer = null; writeCachedChunk(fileId, new Blob(chunks)); }, 1500);
                    }
                }
                if (saveTimer) clearTimeout(saveTimer);

                const blob = new Blob(chunks);
                const blobUrl = URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = blobUrl;
                a.download = decodedName;
                document.body.appendChild(a);
                a.click();
                document.body.removeChild(a);
                setTimeout(() => URL.revokeObjectURL(blobUrl), 8000);
                localStorage.removeItem(resumeKey);
                clearCachedChunk(fileId);

                showToast('Saved ' + decodedName);
            } catch (err) {
                console.error(err);
                showToast('Download interrupted - tap to retry and resume');
            } finally {
                setTimeout(() => progressCard.classList.remove('active'), 1200);
            }
        }

        // Keeps partially downloaded bytes in IndexedDB so an interrupted transfer can
        // continue where it stopped instead of starting over.
        function cacheChunkStore() {
            return new Promise((resolve, reject) => {
                const req = indexedDB.open('dropit_dl', 1);
                req.onupgradeneeded = () => req.result.createObjectStore('chunks');
                req.onsuccess = () => resolve(req.result);
                req.onerror = () => reject(req.error);
            });
        }

        async function writeCachedChunk(fileId, blob) {
            try {
                const db = await cacheChunkStore();
                await new Promise((resolve, reject) => {
                    const tx = db.transaction('chunks', 'readwrite');
                    tx.objectStore('chunks').put(blob, fileId);
                    tx.oncomplete = resolve;
                    tx.onerror = () => reject(tx.error);
                });
            } catch (e) {}
        }

        async function readCachedChunk(fileId) {
            try {
                const db = await cacheChunkStore();
                return await new Promise((resolve, reject) => {
                    const tx = db.transaction('chunks', 'readonly');
                    const r = tx.objectStore('chunks').get(fileId);
                    r.onsuccess = () => resolve(r.result || null);
                    r.onerror = () => reject(r.error);
                });
            } catch (e) { return null; }
        }

        function clearCachedChunk(fileId) {
            try {
                cacheChunkStore().then(db => {
                    const tx = db.transaction('chunks', 'readwrite');
                    tx.objectStore('chunks').delete(fileId);
                }).catch(() => {});
            } catch (e) {}
        }
        async function downloadAllFiles() {
            if (isTransferring || currentSharedFiles.length === 0) return;
            isTransferring = true;
            for (const file of currentSharedFiles) {
                await downloadSingleFile(file.id, encodeURIComponent(file.name));
                await new Promise(r => setTimeout(r, 600));
            }
            isTransferring = false;
        }

        // Staged Files Selection
        function handleFileSelect(event) {
            const files = Array.from(event.target.files);
            if (files.length === 0) return;
            stagedFiles = stagedFiles.concat(files);
            renderStagedFiles();
        }

        function renderStagedFiles() {
            const list = document.getElementById('stagedList');
            const btn = document.getElementById('btnUpload');
            const btnText = document.getElementById('btnUploadText');

            if (stagedFiles.length === 0) {
                list.innerHTML = '';
                btn.style.display = 'none';
                return;
            }

            btn.style.display = 'flex';
            btnText.innerText = `Send ${stagedFiles.length} File${stagedFiles.length > 1 ? 's' : ''} to Mac`;

            list.innerHTML = stagedFiles.map((f, i) => `
                <div class="staged-item">
                    <div class="staged-name">${f.name} (${formatBytes(f.size)})</div>
                    <span style="cursor:pointer; color:var(--danger); font-weight:700;" onclick="removeStaged(${i})">✕</span>
                </div>
            `).join('');
        }

        function removeStaged(index) {
            stagedFiles.splice(index, 1);
            renderStagedFiles();
        }

        // Upload to Mac
        async function startUpload() {
            if (isTransferring || stagedFiles.length === 0) return;
            isTransferring = true;

            const btn = document.getElementById('btnUpload');
            const progressCard = document.getElementById('upProgressCard');
            const progressBar = document.getElementById('upProgressBar');
            const percentText = document.getElementById('upPercent');
            const speedText = document.getElementById('upSpeed');
            const nameText = document.getElementById('upFileName');

            btn.disabled = true;
            progressCard.classList.add('active');

            const totalCount = stagedFiles.length;
            for (let i = 0; i < totalCount; i++) {
                const file = stagedFiles[i];
                nameText.innerText = `Sending (${i + 1}/${totalCount}): ${file.name}`;
                progressBar.style.width = '0%';
                percentText.innerText = '0%';

                await uploadSingleFile(file, (percent, speed) => {
                    progressBar.style.width = percent + '%';
                    percentText.innerText = percent + '%';
                    speedText.innerText = speed;
                });
            }

            if (selectedTargetDeviceName) {
                showToast(`🎉 All files sent to ${selectedTargetDeviceName}!`);
            } else {
                showToast('🎉 All files uploaded to Mac!');
            }
            stagedFiles = [];
            renderStagedFiles();
            btn.disabled = false;
            isTransferring = false;
            setTimeout(() => progressCard.classList.remove('active'), 1500);
        }

        let selectedTargetDeviceId = null;
        let selectedTargetDeviceName = null;

        function selectTargetDevice(deviceId, deviceName) {
            selectedTargetDeviceId = deviceId;
            selectedTargetDeviceName = deviceName;
            closeDevicesModal();
            switchTab('send');
            updateTargetBanner();
            showToast('🎯 Target set: ' + deviceName);
        }

        function clearTargetDevice() {
            selectedTargetDeviceId = null;
            selectedTargetDeviceName = null;
            updateTargetBanner();
        }

        function updateTargetBanner() {
            const banner = document.getElementById('targetDeviceBanner');
            const nameEl = document.getElementById('targetDeviceNameText');
            const titleEl = document.getElementById('sendSectionTitle');
            const btnUploadText = document.getElementById('btnUploadText');
            if (!banner) return;

            if (selectedTargetDeviceId) {
                banner.style.display = 'flex';
                if (nameEl) nameEl.innerText = selectedTargetDeviceName || 'Selected Device';
                if (titleEl) titleEl.innerText = 'Send to ' + (selectedTargetDeviceName || 'Device');
                if (btnUploadText) btnUploadText.innerText = 'Send to ' + (selectedTargetDeviceName || 'Device');
            } else {
                banner.style.display = 'none';
                if (titleEl) titleEl.innerText = 'Upload to Mac';
                if (btnUploadText) btnUploadText.innerText = 'Send to Mac';
            }
        }

        const UPLOAD_CHUNK = 1024 * 1024;

        async function probeUploadOffset(file) {
            try {
                const res = await fetch('/api/upload-status?name=' + encodeURIComponent(file.name) + '&size=' + file.size, {
                    headers: { 'x-device-id': myDeviceId }
                });
                if (!res.ok) return 0;
                const data = await res.json();
                return data && typeof data.offset === 'number' ? data.offset : 0;
            } catch (e) { return 0; }
        }

        function uploadRange(file, start, endExclusive, onProgress) {
            return new Promise((resolve, reject) => {
                const xhr = new XMLHttpRequest();
                const blob = file.slice(start, endExclusive);
                const span = endExclusive - start;
                let lastTime = Date.now();
                let lastLoaded = 0;

                xhr.upload.onprogress = (e) => {
                    const now = Date.now();
                    const elapsed = (now - lastTime) / 1000;
                    let speed = '0 B/s';
                    if (elapsed >= 0.25) {
                        speed = formatSpeed((e.loaded - lastLoaded) / elapsed);
                        lastTime = now;
                        lastLoaded = e.loaded;
                    }
                    const overall = file.size > 0 ? Math.min(100, Math.round(((start + e.loaded) / file.size) * 100)) : 0;
                    onProgress(overall, speed);
                };

                xhr.onload = () => {
                    if (xhr.status >= 200 && xhr.status < 300) {
                        try {
                            const data = JSON.parse(xhr.responseText || '{}');
                            if (data.status === 'reset') { resolve({ reset: true, offset: data.offset || 0 }); return; }
                            resolve({ reset: false, offset: data.offset || endExclusive });
                        } catch (err) { resolve({ reset: false, offset: endExclusive }); }
                    } else {
                        reject(new Error('Upload failed with ' + xhr.status));
                    }
                };
                xhr.onerror = () => reject(new Error('Network error'));
                xhr.ontimeout = () => reject(new Error('Upload timed out'));

                const encodedName = encodeURIComponent(file.name);
                let url = '/api/upload?name=' + encodedName + '&size=' + file.size
                    + '&offset=' + start + '&deviceId=' + myDeviceId;
                if (selectedTargetDeviceId) {
                    url += '&targetDeviceId=' + encodeURIComponent(selectedTargetDeviceId)
                         + '&targetDeviceName=' + encodeURIComponent(selectedTargetDeviceName || '');
                }
                xhr.open('POST', url);
                xhr.setRequestHeader('Content-Type', 'application/octet-stream');
                xhr.setRequestHeader('x-device-id', myDeviceId);
                xhr.setRequestHeader('x-device-name', encodeURIComponent(myDeviceName));
                if (selectedTargetDeviceId) {
                    xhr.setRequestHeader('x-target-device-id', selectedTargetDeviceId);
                    xhr.setRequestHeader('x-target-device-name', encodeURIComponent(selectedTargetDeviceName || ''));
                }
                xhr.send(blob);
            });
        }

        // Uploads in chunks so an interrupted transfer resumes from the last completed
        // chunk instead of restarting the whole file.
        async function uploadSingleFile(file, onProgress) {
            let offset = await probeUploadOffset(file);
            if (offset > file.size) offset = 0;
            if (offset > 0) {
                showToast('Resuming ' + file.name + ' from ' + formatBytes(offset));
            }
            while (offset < file.size) {
                const end = Math.min(offset + UPLOAD_CHUNK, file.size);
                const result = await uploadRange(file, offset, end, onProgress);
                if (result.reset) { offset = result.offset; continue; }
                const next = result.offset;
                if (next <= offset) break;
                offset = next;
            }
            onProgress(100, formatSpeed(0));
            return offset;
        }

        // Browse Mac storage
        let currentFsPath = null;
        let currentFsParent = null;

        function fsIcon(isDir) {            if (isDir) {
                return '<svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">' +
                    '<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"></path></svg>';
            }
            return '<svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">' +
                '<path d="M13 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"></path>' +
                '<polyline points="13 2 13 9 20 9"></polyline></svg>';
        }

        function fsOpen(path) {
            currentFsPath = path;
            fsRefresh();
        }

        async function fsRefresh() {
            const list = document.getElementById('fsList');
            const crumbs = document.getElementById('fsCrumbs');
            const empty = document.getElementById('fsEmpty');
            const errBox = document.getElementById('fsError');
            const path = currentFsPath === null ? '' : currentFsPath;

            fsWireDelegation();
            errBox.style.display = 'none';
            list.innerHTML = '<div style="text-align:center; padding:20px; color:var(--text-secondary);">Loading...</div>';

            try {
                const res = await fetch('/api/fs/list?path=' + encodeURIComponent(path));
                if (!res.ok) {
                    const err = await res.json().catch(() => ({}));
                    throw new Error(err.error || ('Request failed (' + res.status + ')'));
                }
                const data = await res.json();
                currentFsPath = data.path !== undefined ? data.path : path;
                currentFsParent = data.parent;

                renderCrumbs(currentFsPath, currentFsParent);
                renderEntries(entries);
            } catch (err) {
                list.innerHTML = '';
                empty.style.display = 'none';
                errBox.style.display = 'block';
                errBox.innerText = err.message || 'Could not read this folder';
            }
        }

        // Breadcrumbs and file rows are built with DOM APIs and data-attributes rather
        // than inline onclick handlers, so paths and names can never be interpreted as
        // markup or break out of a string.
        function renderCrumbs(currentPath, parentPath) {
            const crumbs = document.getElementById('fsCrumbs');
            crumbs.innerHTML = '';
            const parts = String(currentPath).split('/').filter(p => p.length > 0);

            const add = (label, target, isCurrent) => {
                const span = document.createElement('span');
                span.className = 'fs-crumb' + (isCurrent ? ' current' : '');
                span.textContent = label;
                span.dataset.fsPath = target;
                crumbs.appendChild(span);
            };

            let acc = '';
            add('Mac', '', parts.length === 0);
            parts.forEach((part, i) => {
                const sep = document.createElement('span');
                sep.style.opacity = '.5';
                sep.textContent = '/';
                crumbs.appendChild(sep);
                acc += '/' + part;
                add(part, acc, i === parts.length - 1);
            });

            if (parentPath !== null && parentPath !== undefined) {
                const spacer = document.createElement('span');
                spacer.style.flex = '1';
                crumbs.appendChild(spacer);
                add('↑ Up', String(parentPath), false);
            }
        }

        function renderEntries(entries) {
            const list = document.getElementById('fsList');
            list.innerHTML = '';
            if (!entries.length) return;

            entries.forEach(entry => {
                const row = document.createElement('div');
                row.className = 'fs-item' + (entry.isDirectory ? ' clickable' : '');
                row.dataset.fsPath = entry.path;
                row.dataset.fsIsDir = entry.isDirectory ? '1' : '0';

                const icon = document.createElement('div');
                icon.className = 'fs-icon' + (entry.isDirectory ? ' folder' : '');
                icon.innerHTML = fsIcon(entry.isDirectory);

                const text = document.createElement('div');
                text.style.flex = '1';
                text.style.minWidth = '0';
                const name = document.createElement('div');
                name.className = 'fs-name';
                name.title = entry.name;
                name.textContent = (entry.isSymlink ? '↗ ' : '') + entry.name;
                const meta = document.createElement('div');
                meta.className = 'fs-meta';
                meta.textContent = entry.isDirectory ? 'Folder' : (entry.formattedSize || '');
                text.appendChild(name);
                text.appendChild(meta);

                const actions = document.createElement('div');
                actions.className = 'fs-actions';

                if (!entry.isDirectory) {
                    actions.appendChild(fsButton('Get', 'Get', () => fsDownload(entry.path, entry.name)));
                }
                actions.appendChild(fsButton('Rename', '', () => fsRename(entry.path)));
                actions.appendChild(fsButton('Del', 'danger', () => fsDelete(entry.path, entry.name)));

                row.appendChild(icon);
                row.appendChild(text);
                row.appendChild(actions);
                list.appendChild(row);
            });
        }

        // One delegated listener for the whole browser: clicks on rows and crumbs carry
        // the target path in a data attribute.
        function fsWireDelegation() {
            if (fsWireDelegation.done) return;
            fsWireDelegation.done = true;

            document.getElementById('fsList').addEventListener('click', (event) => {
                if (event.target.closest('[data-fs-act]')) return;
                const row = event.target.closest('.fs-item');
                if (!row || row.dataset.fsIsDir !== '1') return;
                fsOpen(row.dataset.fsPath);
            });
            document.getElementById('fsCrumbs').addEventListener('click', (event) => {
                const crumb = event.target.closest('.fs-crumb');
                if (!crumb) return;
                fsOpen(crumb.dataset.fsPath);
            });
        }

        function fsButton(label, extraClass, handler) {
            const button = document.createElement('button');
            button.className = 'fs-act' + (extraClass ? ' ' + extraClass : '');
            button.textContent = label;
            button.dataset.fsAct = '1';
            button.addEventListener('click', (event) => {
                event.stopPropagation();
                handler();
            });
            return button;
        }

        function fsDownload(path, name) {
            const url = '/api/fs/read?path=' + encodeURIComponent(path) + '&download=1';
            const a = document.createElement('a');
            a.href = url;
            a.download = name;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            showToast('Saving ' + name);
        }

        async function fsPostJson(path, payload) {
            const res = await fetch(path, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload)
            });
            if (!res.ok) {
                const err = await res.json().catch(() => ({}));
                throw new Error(err.error || ('Request failed (' + res.status + ')'));
            }
            return res.json();
        }

        async function fsDelete(path, name) {
            if (!confirm('Delete "' + name + '" from the Mac? This cannot be undone.')) return;
            try {
                await fsPostJson('/api/fs/delete', { path: path });
                showToast('Deleted ' + name);
                fsRefresh();
            } catch (err) {
                showToast('Delete failed: ' + err.message);
            }
        }

        async function fsRename(path) {
            const current = path.split('/').pop();
            const next = prompt('New name for "' + current + '"', current);
            if (!next || next === current) return;
            try {
                await fsPostJson('/api/fs/rename', { path: path, name: next });
                showToast('Renamed to ' + next);
                fsRefresh();
            } catch (err) {
                showToast('Rename failed: ' + err.message);
            }
        }

        function fsNewFolder() {
            document.getElementById('folderNameInput').value = '';
            document.getElementById('folderModal').classList.add('open');
            setTimeout(() => document.getElementById('folderNameInput').focus(), 60);
        }

        function closeFolderModal() {
            document.getElementById('folderModal').classList.remove('open');
        }

        async function confirmNewFolder() {
            const name = document.getElementById('folderNameInput').value.trim();
            if (!name) return;
            try {
                await fsPostJson('/api/fs/mkdir', { path: currentFsPath === null ? '' : currentFsPath, name: name });
                closeFolderModal();
                showToast('Created ' + name);
                fsRefresh();
            } catch (err) {
                showToast('Could not create folder: ' + err.message);
            }
        }

        // History
        async function loadHistory() {
            try {
                const res = await fetch('/api/history');
                if (!res.ok) return;
                const data = await res.json();
                const list = document.getElementById('historyList');
                const empty = document.getElementById('emptyHistory');
                const history = data.history || [];

                if (history.length === 0) {
                    list.innerHTML = '';
                    empty.style.display = 'block';
                    return;
                }
                empty.style.display = 'none';

                list.innerHTML = history.map(item => {
                    const isSent = item.direction === 'sentToDevice';
                    const badgeClass = isSent ? 'badge-sent' : 'badge-received';
                    let badgeText = isSent ? 'From Mac' : 'To Mac';
                    if (item.targetDeviceName && item.targetDeviceId !== 'host_mac') {
                        badgeText = isSent ? `To ${item.targetDeviceName}` : `For ${item.targetDeviceName}`;
                    } else if (item.deviceName && !isSent) {
                        badgeText = `From ${item.deviceName}`;
                    }
                    return `
                        <div class="history-item">
                            <div style="min-width:0; flex:1; margin-right:8px;">
                                <div style="font-size:13px; font-weight:600; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">
                                    ${item.fileName}
                                </div>
                                <div style="font-size:11px; color:var(--text-secondary); margin-top:2px;">
                                    ${item.formattedSize} • ${item.deviceName || 'Device'}
                                </div>
                            </div>
                            <span class="history-badge ${badgeClass}">${badgeText}</span>
                        </div>
                    `;
                }).join('');
            } catch (e) {}
        }

        // Connected Devices Modal
        async function openDevicesModal() {
            const modal = document.getElementById('devicesModal');
            const list = document.getElementById('modalDeviceList');
            modal.classList.add('open');
            list.innerHTML = '<div style="text-align:center; padding:20px; color:var(--text-secondary);">Loading devices...</div>';

            try {
                const res = await fetch('/api/devices');
                const data = await res.json();
                const devices = data.devices || [];

                list.innerHTML = devices.map(d => {
                    const isMe = d.id === myDeviceId;
                    const canSend = !isMe && !d.isBlocked;
                    const safeName = (d.name || 'Device').replace(/'/g, "\\'");
                    return `
                        <div class="device-item ${canSend ? 'clickable' : ''}">
                            <div class="device-info-left" ${canSend ? `onclick="selectTargetDevice('${d.id}', '${safeName}')"` : ''} style="${canSend ? 'cursor:pointer;' : ''}">
                                <div class="device-icon-box">
                                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                        <rect x="5" y="2" width="14" height="20" rx="2" ry="2"></polyline>
                                        <line x1="12" y1="18" x2="12.01" y2="18"></line>
                                    </svg>
                                </div>
                                <div>
                                    <div style="font-size:14px; font-weight:600;">
                                        ${d.name} ${isMe ? '<span style="color:var(--accent); font-size:11px;">(You)</span>' : ''}
                                    </div>
                                    <div style="font-size:11px; color:var(--text-secondary); margin-top:2px;">
                                        ${d.ip} • ${d.isHost ? 'Host' : (d.isBlocked ? 'Disconnected' : 'Active')}
                                    </div>
                                </div>
                            </div>
                            <div style="display:flex; align-items:center; gap:8px;">
                                ${canSend ? `
                                    <button class="btn-device-send" onclick="selectTargetDevice('${d.id}', '${safeName}')">
                                        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
                                            <line x1="22" y1="2" x2="11" y2="13"></line>
                                            <polygon points="22 2 15 22 11 13 2 9 22 2"></polygon>
                                        </svg>
                                        <span>Send</span>
                                    </button>
                                ` : ''}
                                ${d.isBlocked ? '<span style="font-size:11px; color:var(--danger); font-weight:600;">Blocked</span>' : '<span style="font-size:11px; color:var(--success); font-weight:600;">Connected</span>'}
                            </div>
                        </div>
                    `;
                }).join('');
            } catch (e) {
                list.innerHTML = '<div style="text-align:center; color:var(--danger);">Failed to load devices</div>';
            }
        }

        function closeDevicesModal() {
            document.getElementById('devicesModal').classList.remove('open');
        }

        // Disconnect Management
        async function disconnectSelf() {
            if (!confirm('Are you sure you want to disconnect from this Dropit session?')) return;
            try {
                await fetch('/api/disconnect', {
                    method: 'POST',
                    headers: { 'x-device-id': myDeviceId }
                });
            } catch (e) {}
            showDisconnectedState();
        }

        function showDisconnectedState() {
            isDisconnected = true;
            document.getElementById('disconnectedScreen').classList.add('show');
            closeDevicesModal();
        }

        async function reconnectSelf() {
            // Generate new device identity or reset blocked state
            localStorage.removeItem('dropit_device_id');
            window.location.reload();
        }

        function formatBytes(bytes) {
            if (!bytes || bytes === 0) return '0 B';
            const k = 1024;
            const sizes = ['B', 'KB', 'MB', 'GB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
        }

        function formatSpeed(bytesPerSec) {
            return formatBytes(bytesPerSec) + '/s';
        }
    </script>
</body>
</html>
"""
    }
}
