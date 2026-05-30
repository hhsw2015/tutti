#!/usr/bin/env python3
"""Inject onboarding translations into Localizable.xcstrings.

Source language is zh-Hans (the key IS the Chinese string), so only non-source
locales are written. Run from repo root. Idempotent: re-running overwrites the
listed locales for the listed keys and leaves everything else (and key order)
untouched.
"""
import json

PATH = "Tutti/Localizable.xcstrings"

# key (zh-Hans source) -> { locale: value }
DATA = {
    "把一路音频同时送到多个设备。\n音箱、AirPods、HomePod —— 播放同一段声音。": {
        "en": "Send one audio stream to every device at once.\nSpeakers, AirPods, HomePod — all playing the same sound.",
        "zh-Hant": "把一路音訊同時送到多個裝置。\n喇叭、AirPods、HomePod —— 播放同一段聲音。",
        "ja": "一つの音声を複数のデバイスへ同時に送ります。\nスピーカー、AirPods、HomePod —— すべてで同じ音を再生。",
        "ko": "하나의 오디오를 여러 기기로 동시에 전송합니다.\n스피커, AirPods, HomePod — 모두 같은 소리를 재생합니다.",
        "fr": "Diffusez un même flux audio sur tous vos appareils à la fois.\nEnceintes, AirPods, HomePod — tous jouent le même son.",
        "de": "Sende einen Audiostream gleichzeitig an beliebig viele Geräte.\nLautsprecher, AirPods, HomePod — alle spielen denselben Ton.",
        "it": "Invia un unico flusso audio a tutti i dispositivi contemporaneamente.\nAltoparlanti, AirPods, HomePod — tutti riproducono lo stesso suono.",
        "es": "Envía una sola señal de audio a todos los dispositivos a la vez.\nAltavoces, AirPods, HomePod: todos reproducen el mismo sonido.",
    },
    "多设备同步": {
        "en": "Multi-Device Sync", "zh-Hant": "多裝置同步", "ja": "マルチデバイス同期",
        "ko": "다중 기기 동기화", "fr": "Synchronisation multi-appareils",
        "de": "Multi-Geräte-Sync", "it": "Sincronizzazione multi-dispositivo",
        "es": "Sincronización multidispositivo",
    },
    "同一音轨，零延迟": {
        "en": "One track, zero lag", "zh-Hant": "同一音軌，零延遲", "ja": "同じ音、遅延ゼロ",
        "ko": "같은 트랙, 지연 없음", "fr": "Même piste, zéro latence",
        "de": "Ein Track, null Verzögerung", "it": "Stessa traccia, zero ritardo",
        "es": "Una pista, cero retardo",
    },
    "菜单栏常驻": {
        "en": "Lives in the Menu Bar", "zh-Hant": "常駐選單列", "ja": "メニューバーに常駐",
        "ko": "메뉴 막대에 상주", "fr": "Toujours dans la barre des menus",
        "de": "Immer in der Menüleiste", "it": "Sempre nella barra dei menu",
        "es": "Siempre en la barra de menús",
    },
    "随手切换输出": {
        "en": "Switch outputs on the fly", "zh-Hant": "隨手切換輸出", "ja": "出力をすぐに切り替え",
        "ko": "출력을 즉시 전환", "fr": "Changez de sortie à la volée",
        "de": "Ausgänge im Handumdrehen wechseln", "it": "Cambia uscita al volo",
        "es": "Cambia de salida al instante",
    },
    "开始": {
        "en": "Get Started", "zh-Hant": "開始", "ja": "はじめる", "ko": "시작하기",
        "fr": "Commencer", "de": "Loslegen", "it": "Inizia", "es": "Empezar",
    },
    "开启辅助功能权限": {
        "en": "Enable Accessibility Access", "zh-Hant": "開啟輔助使用權限",
        "ja": "アクセシビリティを許可", "ko": "손쉬운 사용 권한 허용",
        "fr": "Autoriser l'accès à l'accessibilité", "de": "Bedienungshilfen-Zugriff aktivieren",
        "it": "Abilita l'accesso all'accessibilità", "es": "Permitir acceso a accesibilidad",
    },
    "权限已开启": {
        "en": "Access Granted", "zh-Hant": "權限已開啟", "ja": "許可されました",
        "ko": "권한이 허용됨", "fr": "Accès autorisé", "de": "Zugriff erteilt",
        "it": "Accesso concesso", "es": "Acceso concedido",
    },
    "现在你可以用键盘音量键直接控制 Tutti 的聚合输出。": {
        "en": "You can now use the keyboard volume keys to control Tutti's combined output directly.",
        "zh-Hant": "現在你可以用鍵盤音量鍵直接控制 Tutti 的聚合輸出。",
        "ja": "キーボードの音量キーで Tutti の統合出力を直接コントロールできます。",
        "ko": "이제 키보드 음량 키로 Tutti의 통합 출력을 직접 제어할 수 있습니다.",
        "fr": "Vous pouvez désormais utiliser les touches de volume du clavier pour contrôler directement la sortie combinée de Tutti.",
        "de": "Du kannst jetzt die Lautstärketasten der Tastatur nutzen, um Tuttis kombinierte Ausgabe direkt zu steuern.",
        "it": "Ora puoi usare i tasti del volume della tastiera per controllare direttamente l'uscita combinata di Tutti.",
        "es": "Ahora puedes usar las teclas de volumen del teclado para controlar directamente la salida combinada de Tutti.",
    },
    "授权后，键盘音量键能直接控制 Tutti 的聚合输出。这是 Pro 特性。": {
        "en": "Once authorized, the keyboard volume keys control Tutti's combined output directly. This is a Pro feature.",
        "zh-Hant": "授權後，鍵盤音量鍵能直接控制 Tutti 的聚合輸出。這是 Pro 功能。",
        "ja": "許可すると、キーボードの音量キーで Tutti の統合出力を直接コントロールできます。これは Pro 機能です。",
        "ko": "권한을 허용하면 키보드 음량 키로 Tutti의 통합 출력을 직접 제어할 수 있습니다. Pro 기능입니다.",
        "fr": "Une fois autorisé, les touches de volume du clavier contrôlent directement la sortie combinée de Tutti. C'est une fonctionnalité Pro.",
        "de": "Nach der Freigabe steuern die Lautstärketasten der Tastatur Tuttis kombinierte Ausgabe direkt. Dies ist eine Pro-Funktion.",
        "it": "Una volta autorizzato, i tasti del volume della tastiera controllano direttamente l'uscita combinata di Tutti. È una funzione Pro.",
        "es": "Una vez autorizado, las teclas de volumen del teclado controlan directamente la salida combinada de Tutti. Es una función Pro.",
    },
    "返回": {
        "en": "Back", "zh-Hant": "返回", "ja": "戻る", "ko": "뒤로",
        "fr": "Retour", "de": "Zurück", "it": "Indietro", "es": "Atrás",
    },
    "使用 F11 / F12 与音量键": {
        "en": "Use F11 / F12 and the volume keys", "zh-Hant": "使用 F11 / F12 與音量鍵",
        "ja": "F11 / F12 と音量キーを使用", "ko": "F11 / F12 및 음량 키 사용",
        "fr": "Utiliser F11 / F12 et les touches de volume",
        "de": "F11 / F12 und die Lautstärketasten verwenden",
        "it": "Usa F11 / F12 e i tasti del volume", "es": "Usar F11 / F12 y las teclas de volumen",
    },
    "替代系统默认音频管理，使音量调节作用于聚合输出而不是单一设备。": {
        "en": "Replaces the system's default audio handling so volume changes affect the combined output instead of a single device.",
        "zh-Hant": "取代系統預設的音訊管理，讓音量調整作用於聚合輸出，而非單一裝置。",
        "ja": "システム標準の音声処理を置き換え、音量調整が単一デバイスではなく統合出力に作用します。",
        "ko": "시스템 기본 오디오 처리를 대체하여 음량 조절이 단일 기기가 아닌 통합 출력에 적용됩니다.",
        "fr": "Remplace la gestion audio par défaut du système pour que les réglages de volume agissent sur la sortie combinée plutôt que sur un seul appareil.",
        "de": "Ersetzt die Standard-Audioverwaltung des Systems, sodass Lautstärkeänderungen die kombinierte Ausgabe statt eines einzelnen Geräts betreffen.",
        "it": "Sostituisce la gestione audio predefinita del sistema, così le modifiche al volume agiscono sull'uscita combinata invece che su un singolo dispositivo.",
        "es": "Sustituye la gestión de audio predeterminada del sistema para que los cambios de volumen afecten a la salida combinada en lugar de a un solo dispositivo.",
    },
    "未授权": {
        "en": "Not Authorized", "zh-Hant": "未授權", "ja": "未許可", "ko": "권한 없음",
        "fr": "Non autorisé", "de": "Nicht autorisiert", "it": "Non autorizzato", "es": "No autorizado",
    },
    "稍后在设置中开启": {
        "en": "Enable later in Settings", "zh-Hant": "稍後在設定中開啟",
        "ja": "後で設定で有効にする", "ko": "나중에 설정에서 활성화",
        "fr": "Activer plus tard dans les réglages", "de": "Später in den Einstellungen aktivieren",
        "it": "Abilita più tardi nelle impostazioni", "es": "Activar más tarde en Ajustes",
    },
    "打开设置": {
        "en": "Open Settings", "zh-Hant": "開啟設定", "ja": "設定を開く", "ko": "설정 열기",
        "fr": "Ouvrir les réglages", "de": "Einstellungen öffnen",
        "it": "Apri impostazioni", "es": "Abrir ajustes",
    },
    "下一步": {
        "en": "Next", "zh-Hant": "下一步", "ja": "次へ", "ko": "다음",
        "fr": "Suivant", "de": "Weiter", "it": "Avanti", "es": "Siguiente",
    },
    "点击「打开设置」会跳转到 `系统设置 › 隐私与安全性 › 辅助功能`，把 Tutti 的开关打开即可。": {
        "en": "Click \"Open Settings\" to jump to `System Settings › Privacy & Security › Accessibility`, then turn on the switch for Tutti.",
        "zh-Hant": "點一下「開啟設定」會跳到 `系統設定 › 隱私權與安全性 › 輔助使用`，把 Tutti 的開關打開即可。",
        "ja": "「設定を開く」をクリックすると `システム設定 › プライバシーとセキュリティ › アクセシビリティ` が開くので、Tutti のスイッチをオンにしてください。",
        "ko": "「설정 열기」를 클릭하면 `시스템 설정 › 개인정보 보호 및 보안 › 손쉬운 사용`으로 이동합니다. Tutti의 스위치를 켜 주세요.",
        "fr": "Cliquez sur « Ouvrir les réglages » pour accéder à `Réglages Système › Confidentialité et sécurité › Accessibilité`, puis activez l'interrupteur pour Tutti.",
        "de": "Klicke auf „Einstellungen öffnen“, um zu `Systemeinstellungen › Datenschutz & Sicherheit › Bedienungshilfen` zu gelangen, und aktiviere dort den Schalter für Tutti.",
        "it": "Fai clic su «Apri impostazioni» per aprire `Impostazioni di Sistema › Privacy e sicurezza › Accessibilità`, poi attiva l'interruttore per Tutti.",
        "es": "Haz clic en «Abrir ajustes» para ir a `Ajustes del Sistema › Privacidad y seguridad › Accesibilidad` y activa el interruptor de Tutti.",
    },
    "点击「打开系统设置」会跳到 `控制中心`，把 `声音` 一栏的「在菜单栏中显示」改为「不显示」即可。": {
        "en": "Click \"Open System Settings\" to jump to `Control Center`; under `Sound`, change \"Show in Menu Bar\" to \"Don't Show\".",
        "zh-Hant": "點一下「開啟系統設定」會跳到 `控制中心`，把 `聲音` 一欄的「在選單列中顯示」改為「不顯示」即可。",
        "ja": "「システム設定を開く」をクリックすると `コントロールセンター` が開きます。`サウンド` の項目で「メニューバーに表示」を「表示しない」に変更してください。",
        "ko": "「시스템 설정 열기」를 클릭하면 `제어 센터`로 이동합니다. `사운드` 항목에서 \"메뉴 막대에 보기\"를 \"보지 않기\"로 변경하세요.",
        "fr": "Cliquez sur « Ouvrir les Réglages système » pour accéder au `Centre de contrôle` ; sous `Son`, remplacez « Afficher dans la barre des menus » par « Ne pas afficher ».",
        "de": "Klicke auf „Systemeinstellungen öffnen“, um zum `Kontrollzentrum` zu gelangen; ändere unter `Ton` „In Menüleiste anzeigen“ auf „Nicht anzeigen“.",
        "it": "Fai clic su «Apri Impostazioni di sistema» per aprire `Centro di Controllo`; in `Suono`, cambia «Mostra nella barra dei menu» in «Non mostrare».",
        "es": "Haz clic en «Abrir Ajustes del sistema» para ir al `Centro de control`; en `Sonido`, cambia «Mostrar en la barra de menús» a «No mostrar».",
    },
}


def main():
    with open(PATH, encoding="utf-8") as f:
        cat = json.load(f)
    strings = cat["strings"]
    for key, locs in DATA.items():
        entry = strings.setdefault(key, {})
        entry.setdefault("extractionState", "manual")
        L = entry.setdefault("localizations", {})
        for loc, val in locs.items():
            L[loc] = {"stringUnit": {"state": "translated", "value": val}}
    with open(PATH, "w", encoding="utf-8") as f:
        json.dump(cat, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"done: {len(DATA)} keys updated")


if __name__ == "__main__":
    main()
