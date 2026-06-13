import SwiftUI

// MARK: - ServiceInfo

struct ServiceInfo {
    let assetName: String?
    let brandColor: Color
    let foregroundColor: Color
}

// MARK: - ServiceIconResolver

enum ServiceIconResolver {
    // MARK: - Display issuer

    static func displayIssuer(issuer: String?, name: String) -> String? {
        let trimmedIssuer = issuer?.trimmingCharacters(in: .whitespaces) ?? ""
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        if !trimmedIssuer.isEmpty {
            if !looksLikeEmail(trimmedIssuer) {
                return trimmedIssuer
            }
            return friendlyName(fromEmail: trimmedIssuer) ?? trimmedIssuer
        }

        if looksLikeEmail(trimmedName), let friendly = friendlyName(fromEmail: trimmedName) {
            return friendly
        }

        return nil
    }

    // MARK: - Lookup

    static func resolve(issuer: String?, name: String) -> ServiceInfo? {
        let trimmedIssuer = issuer?.trimmingCharacters(in: .whitespaces) ?? ""
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let derived = displayIssuer(issuer: issuer, name: name)

        let candidates: [String]
        if !trimmedIssuer.isEmpty {
            candidates = [derived, trimmedIssuer]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
        } else {
            let cleaned = cleanForMatching(trimmedName)
            candidates = [derived, cleaned.isEmpty ? nil : cleaned]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
        }

        var seen = Set<String>()
        let ordered = candidates.filter { seen.insert($0).inserted }

        for candidate in ordered {
            if let info = exactMatch(candidate) { return info }
        }
        for candidate in ordered {
            if let info = prefixMatch(candidate) { return info }
        }
        for candidate in ordered {
            if let info = containsMatch(candidate) { return info }
        }
        return nil
    }

    // MARK: - Email validation

    private static func looksLikeEmail(_ string: String) -> Bool {
        guard !string.contains(" "),
              !string.contains("("),
              !string.contains(")")
        else { return false }
        let parts = string.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && !parts[1].isEmpty
    }

    private static func cleanForMatching(_ string: String) -> String {
        let filtered = string.components(separatedBy: .whitespaces).filter { word in
            let inner = word.trimmingCharacters(in: CharacterSet(charactersIn: "()[]<>"))
            return !looksLikeEmail(inner)
        }
        return filtered
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "() "))
    }

    // MARK: - Email domain extraction (no network calls)

    private static func friendlyName(fromEmail email: String) -> String? {
        guard let domain = email.split(separator: "@").last.map(String.init)
        else { return nil }

        let lower = domain.lowercased()

        if let name = domainNames[lower] { return name }

        let parts = lower.split(separator: ".").map(String.init)
        if parts.count > 2 {
            let root = parts.suffix(2).joined(separator: ".")
            if let name = domainNames[root] { return name }
        }

        let label = parts.count >= 2 ? parts[parts.count - 2] : parts.first
        return label.map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }

    private static let domainNames: [String: String] = [
        "gmail.com": "Gmail",
        "googlemail.com": "Gmail",
        "yahoo.com": "Yahoo",
        "yahoo.co.uk": "Yahoo",
        "yahoo.co.jp": "Yahoo",
        "yahoo.fr": "Yahoo",
        "yahoo.de": "Yahoo",
        "ymail.com": "Yahoo",
        "hotmail.com": "Hotmail",
        "hotmail.co.uk": "Hotmail",
        "hotmail.fr": "Hotmail",
        "hotmail.de": "Hotmail",
        "outlook.com": "Outlook",
        "outlook.co.uk": "Outlook",
        "live.com": "Microsoft",
        "live.co.uk": "Microsoft",
        "msn.com": "Microsoft",
        "icloud.com": "iCloud",
        "me.com": "iCloud",
        "mac.com": "iCloud",
        "apple.com": "Apple",
        "protonmail.com": "Proton Mail",
        "proton.me": "Proton Mail",
        "pm.me": "Proton Mail",
        "fastmail.com": "Fastmail",
        "fastmail.fm": "Fastmail",
        "zoho.com": "Zoho",
        "aol.com": "AOL",
        "yandex.com": "Yandex",
        "yandex.ru": "Yandex",
        "mail.com": "Mail.com",
        "tutanota.com": "Tutanota",
        "tuta.io": "Tutanota",
        "hey.com": "HEY",
        "mailfence.com": "Mailfence",
        "gmx.com": "GMX",
        "gmx.de": "GMX",
        "posteo.de": "Posteo",

        "github.com": "GitHub",
        "gitlab.com": "GitLab",
        "bitbucket.org": "Bitbucket",
        "atlassian.com": "Atlassian",
        "digitalocean.com": "DigitalOcean",
        "heroku.com": "Heroku",
        "vercel.com": "Vercel",
        "netlify.com": "Netlify",
        "cloudflare.com": "Cloudflare",
        "linode.com": "Linode",
        "vultr.com": "Vultr",
        "namecheap.com": "Namecheap",
        "godaddy.com": "GoDaddy",
        "docker.com": "Docker",
        "npmjs.com": "npm",
        "auth0.com": "Auth0",
        "okta.com": "Okta",
        "twilio.com": "Twilio",
        "sendgrid.com": "SendGrid",
        "datadog.com": "Datadog",
        "sentry.io": "Sentry",

        "facebook.com": "Facebook",
        "instagram.com": "Instagram",
        "twitter.com": "Twitter",
        "x.com": "X",
        "linkedin.com": "LinkedIn",
        "reddit.com": "Reddit",
        "discord.com": "Discord",
        "slack.com": "Slack",
        "telegram.org": "Telegram",
        "signal.org": "Signal",
        "whatsapp.com": "WhatsApp",
        "snapchat.com": "Snapchat",
        "tiktok.com": "TikTok",
        "pinterest.com": "Pinterest",
        "tumblr.com": "Tumblr",
        "twitch.tv": "Twitch",
        "mastodon.social": "Mastodon",
        "patreon.com": "Patreon",
        "substack.com": "Substack",
        "medium.com": "Medium",

        "google.com": "Google",
        "microsoft.com": "Microsoft",
        "amazon.com": "Amazon",
        "dropbox.com": "Dropbox",
        "notion.so": "Notion",
        "figma.com": "Figma",
        "canva.com": "Canva",
        "zoom.us": "Zoom",
        "shopify.com": "Shopify",
        "stripe.com": "Stripe",

        "paypal.com": "PayPal",
        "wise.com": "Wise",
        "revolut.com": "Revolut",
        "coinbase.com": "Coinbase",
        "binance.com": "Binance",
        "kraken.com": "Kraken",
        "crypto.com": "Crypto.com",
        "robinhood.com": "Robinhood",
        "venmo.com": "Venmo",

        "steampowered.com": "Steam",
        "epicgames.com": "Epic Games",
        "battle.net": "Battle.net",
        "blizzard.com": "Blizzard",
        "nintendo.com": "Nintendo",
        "playstation.com": "PlayStation",
        "ea.com": "EA",
        "ubisoft.com": "Ubisoft",
        "gog.com": "GOG",

        "nordvpn.com": "NordVPN",
        "expressvpn.com": "ExpressVPN",
        "1password.com": "1Password",
        "bitwarden.com": "Bitwarden",
        "lastpass.com": "LastPass",
        "dashlane.com": "Dashlane",

        "airbnb.com": "Airbnb",
        "booking.com": "Booking.com",
        "uber.com": "Uber",
        "lyft.com": "Lyft",
    ]

    // MARK: - Private helpers

    private static func exactMatch(_ raw: String) -> ServiceInfo? {
        let key = raw.lowercased()
        return catalog[key]
    }

    private static func prefixMatch(_ raw: String) -> ServiceInfo? {
        let key = raw.lowercased()
        return catalog.first(where: { key.hasPrefix($0.key) || $0.key.hasPrefix(key) })?.value
    }

    private static func containsMatch(_ raw: String) -> ServiceInfo? {
        let key = raw.lowercased()
        return catalog.first(where: { key.contains($0.key) || $0.key.contains(key) })?.value
    }

    // MARK: - Catalog

    private static let catalog: [String: ServiceInfo] = {
        func entry(_ assetName: String? = nil, hex: UInt32, light: Bool = true) -> ServiceInfo {
            let bg = Color(hex: hex)
            let fg: Color = light ? Color(hex: hex).lightened(by: 0.55) : Color(hex: hex).darkened(by: 0.55)
            return ServiceInfo(assetName: assetName, brandColor: bg, foregroundColor: fg)
        }
        func w(_ assetName: String? = nil, hex: UInt32) -> ServiceInfo { // white-fg variant
            ServiceInfo(assetName: assetName, brandColor: Color(hex: hex), foregroundColor: .white.opacity(0.9))
        }
        func b(_ assetName: String? = nil, hex: UInt32) -> ServiceInfo { // black-fg variant
            ServiceInfo(assetName: assetName, brandColor: Color(hex: hex), foregroundColor: Color(hex: 0x1A1A1A))
        }

        return [
            "google": w(hex: 0x4285F4),
            "gmail": w(hex: 0xEA4335),
            "google workspace": w(hex: 0x4285F4),
            "youtube": w(hex: 0xFF0000),
            "google cloud": w(hex: 0x4285F4),
            "firebase": w(hex: 0xFFCA28),

            "apple": w(hex: 0x000000),
            "icloud": w(hex: 0x3693F3),
            "apple id": w(hex: 0x000000),

            "microsoft": w(hex: 0x5E5E5E),
            "outlook": w(hex: 0x0078D4),
            "hotmail": w(hex: 0x0078D4),
            "azure": w(hex: 0x0078D4),
            "xbox": w(hex: 0x107C10),
            "teams": w(hex: 0x6264A7),
            "github": w(hex: 0x181717),

            "amazon": b(hex: 0xFF9900),
            "aws": b(hex: 0xFF9900),
            "amazon web services": b(hex: 0xFF9900),
            "twitch": w(hex: 0x9146FF),

            "facebook": w(hex: 0x0866FF),
            "meta": w(hex: 0x0866FF),
            "instagram": w(hex: 0xE4405F),
            "whatsapp": w(hex: 0x25D366),

            "twitter": w(hex: 0x000000),
            "x.com": w(hex: 0x000000),
            "x": w(hex: 0x000000),

            "dropbox": w(hex: 0x0061FF),
            "slack": w(hex: 0x4A154B),
            "notion": b(hex: 0xFFFFFF),
            "atlassian": w(hex: 0x0052CC),
            "jira": w(hex: 0x0052CC),
            "confluence": w(hex: 0x172B4D),
            "bitbucket": w(hex: 0x0052CC),
            "trello": w(hex: 0x0052CC),
            "asana": w(hex: 0xF06A6A),
            "monday.com": w(hex: 0xFF3750),
            "airtable": w(hex: 0x18BFFF),
            "figma": w(hex: 0xF24E1E),
            "adobe": w(hex: 0xFF0000),
            "canva": w(hex: 0x00C4CC),
            "zoom": w(hex: 0x2D8CFF),
            "1password": b(hex: 0x1A8CFF),
            "bitwarden": w(hex: 0x175DDC),
            "lastpass": w(hex: 0xD32D27),
            "dashlane": w(hex: 0x00ADE0),
            "keeper": w(hex: 0x00AEEF),
            "nordpass": w(hex: 0x4687FF),

            "reddit": w(hex: 0xFF4500),
            "linkedin": w(hex: 0x0A66C2),
            "discord": w(hex: 0x5865F2),
            "telegram": w(hex: 0x2CA5E0),
            "signal": w(hex: 0x3A76F0),
            "snapchat": b(hex: 0xFFFC00),
            "tiktok": w(hex: 0x000000),
            "pinterest": w(hex: 0xE60023),
            "tumblr": w(hex: 0x35465C),
            "mastodon": w(hex: 0x6364FF),
            "patreon": w(hex: 0xFF424D),
            "substack": w(hex: 0xFF6719),
            "medium": w(hex: 0x000000),
            "devto": w(hex: 0x0A0A0A),
            "dev.to": w(hex: 0x0A0A0A),
            "stackoverflow": w(hex: 0xF58025),
            "hackernews": b(hex: 0xFF6600),
            "hacker news": b(hex: 0xFF6600),

            "steam": w(hex: 0x000000),
            "epic games": w(hex: 0x2563EB),
            "epicgames": w(hex: 0x2563EB),
            "nintendo": w(hex: 0xE60012),
            "playstation": w(hex: 0x003791),
            "battle.net": w(hex: 0x148EFF),
            "battlenet": w(hex: 0x148EFF),
            "blizzard": w(hex: 0x148EFF),
            "ea": w(hex: 0x000000),
            "origin": w(hex: 0xF56C2D),
            "ubisoft": w(hex: 0x000000),
            "gog": w(hex: 0x86328A),
            "riot games": w(hex: 0xD32936),
            "riotgames": w(hex: 0xD32936),
            "genshin impact": w(hex: 0x2F6FEB),

            "netflix": w(hex: 0xE50914),
            "spotify": b(hex: 0x1DB954),
            "disney": w(hex: 0x113CCF),
            "disney+": w(hex: 0x113CCF),
            "hulu": w(hex: 0x1CE783),
            "hbo": w(hex: 0x8258FA),
            "apple tv": w(hex: 0x000000),
            "prime video": w(hex: 0x00A8E0),
            "amazon prime": b(hex: 0xFF9900),

            "paypal": w(hex: 0x003087),
            "stripe": w(hex: 0x635BFF),
            "wise": w(hex: 0x9FE870),
            "revolut": w(hex: 0x0666EB),
            "cash app": w(hex: 0x00D54B),
            "cashapp": w(hex: 0x00D54B),
            "venmo": w(hex: 0x008CFF),
            "square": w(hex: 0x3E4348),
            "robinhood": b(hex: 0x00C805),
            "coinbase": w(hex: 0x0052FF),
            "binance": b(hex: 0xF0B90B),
            "kraken": w(hex: 0x5741D9),
            "crypto.com": w(hex: 0x002D74),

            "cloudflare": b(hex: 0xF48120),
            "digitalocean": w(hex: 0x0080FF),
            "heroku": w(hex: 0x430098),
            "vercel": b(hex: 0x000000),
            "netlify": w(hex: 0x00C7B7),
            "gitlab": w(hex: 0xFC6D26),
            "docker": w(hex: 0x2496ED),
            "npm": w(hex: 0xCB3837),
            "fastly": w(hex: 0xFF282D),
            "linode": w(hex: 0x00A95C),
            "vultr": w(hex: 0x007BFC),
            "namecheap": w(hex: 0xDE3723),
            "godaddy": w(hex: 0x1BDBDB),
            "cloudinary": w(hex: 0x3448C5),
            "sendgrid": w(hex: 0x1A82E2),
            "twilio": w(hex: 0xF22F46),
            "auth0": w(hex: 0xEB5424),
            "okta": w(hex: 0x007DC1),
            "datadog": w(hex: 0x632CA6),
            "sentry": w(hex: 0x362D59),

            "shopify": b(hex: 0x96BF48),
            "etsy": w(hex: 0xF16521),
            "ebay": w(hex: 0x0064D2),
            "aliexpress": w(hex: 0xFF6A00),
            "alibaba": w(hex: 0xFF6A00),

            "proton": w(hex: 0x6D4AFF),
            "protonmail": w(hex: 0x6D4AFF),
            "fastmail": w(hex: 0x2F71DA),
            "zoho": w(hex: 0xE42527),
            "mailchimp": b(hex: 0xFFE01B),

            "nordvpn": w(hex: 0x4687FF),
            "expressvpn": w(hex: 0xDA3940),
            "mullvad": b(hex: 0xFFD040),
            "protonvpn": w(hex: 0x6D4AFF),

            "airbnb": w(hex: 0xFF5A5F),
            "booking.com": w(hex: 0x003580),
            "uber": w(hex: 0x000000),
            "lyft": w(hex: 0xFF00BF),
        ]
    }()
}

// MARK: - Color helpers

private extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    func lightened(by amount: Double) -> Color {
        opacity(1).blended(with: .white, ratio: amount)
    }

    func darkened(by amount: Double) -> Color {
        opacity(1).blended(with: .black, ratio: amount)
    }

    func blended(with other: Color, ratio: Double) -> Color {
        guard let c1 = UIColor(self).cgColor.components,
              let c2 = UIColor(other).cgColor.components else { return self }
        let r = c1[0] * (1 - ratio) + c2[0] * ratio
        let g = c1[1] * (1 - ratio) + c2[1] * ratio
        let b = c1[2] * (1 - ratio) + c2[2] * ratio
        return Color(red: Double(r), green: Double(g), blue: Double(b))
    }
}
