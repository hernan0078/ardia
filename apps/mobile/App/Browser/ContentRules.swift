import Foundation

enum ContentRules {
  static let trackerDomains = [
    "google-analytics.com", "googletagmanager.com", "googletagservices.com", "doubleclick.net", "scorecardresearch.com",
    "hotjar.com", "mixpanel.com", "segment.io", "segment.com", "amplitude.com", "fullstory.com", "mouseflow.com",
    "quantserve.com", "chartbeat.com", "chartbeat.net", "newrelic.com", "nr-data.net", "clarity.ms", "bat.bing.com",
    "connect.facebook.net", "analytics.twitter.com", "ads-twitter.com", "static.ads-twitter.com", "analytics.tiktok.com",
    "snap.licdn.com", "px.ads.linkedin.com", "branch.io", "app-measurement.com", "crashlytics.com", "adjust.com",
    "appsflyer.com", "kochava.com", "optimizely.com", "heapanalytics.com", "pendo.io", "krxd.net", "bluekai.com",
    "demdex.net", "omtrdc.net", "everesttech.net", "rlcdn.com", "adsrvr.org", "mathtag.com", "tapad.com",
  ]

  static let adDomains = [
    "googlesyndication.com", "pagead2.googlesyndication.com", "adservice.google.com", "amazon-adsystem.com",
    "adnxs.com", "criteo.com", "criteo.net", "taboola.com", "outbrain.com", "pubmatic.com", "rubiconproject.com",
    "openx.net", "casalemedia.com", "moatads.com", "adsafeprotected.com", "doubleverify.com", "media.net",
    "sharethrough.com", "teads.tv", "yieldmo.com", "smartadserver.com", "zedo.com", "revcontent.com", "mgid.com",
    "adform.net", "33across.com", "indexww.com", "sovrn.com", "lijit.com", "contextweb.com", "bidswitch.net",
  ]

  static let cookieBannerSelectors = [
    "#onetrust-banner-sdk", "#onetrust-consent-sdk", ".onetrust-pc-dark-filter", "#CybotCookiebotDialog",
    "#CybotCookiebotDialogBodyUnderlay", ".qc-cmp2-container", "#qc-cmp2-container", ".fc-consent-root",
    "#didomi-host", ".didomi-popup-open", "#truste-consent-track", ".truste_overlay", ".truste_box_overlay",
    "#usercentrics-root", ".cc-window", ".cc-banner", "#cookie-law-info-bar", ".cookie-notice-container",
    "#cookie-notice", "#gdpr-cookie-message", ".cmp-container", "#sp_message_container_", "[id^='sp_message_container']",
    ".osano-cm-window", "#hs-eu-cookie-confirmation", ".js-consent-banner", "[aria-label='cookieconsent']",
  ]

  static func json(ads: Bool, trackers: Bool, cookieBanners: Bool, allowed: [String]) -> String {
    let unless = allowed.map { "*" + $0 }
    func scoped(_ trigger: [String: Any]) -> [String: Any] {
      var t = trigger
      if !unless.isEmpty { t["unless-domain"] = unless }
      return t
    }
    var rules: [[String: Any]] = []
    let domains = (trackers ? trackerDomains : []) + (ads ? adDomains : [])
    for domain in domains {
      let escaped = NSRegularExpression.escapedPattern(for: domain)
      rules.append([
        "trigger": scoped(["url-filter": "^https?://([^/]*\\.)?\(escaped)[:/]", "load-type": ["third-party"]]),
        "action": ["type": "block"],
      ])
    }
    if cookieBanners {
      rules.append(["trigger": scoped(["url-filter": ".*"]), "action": ["type": "css-display-none", "selector": cookieBannerSelectors.joined(separator: ", ")]])
    }
    if rules.isEmpty {
      rules.append(["trigger": ["url-filter": "^ardia-never-matches:"], "action": ["type": "block"]])
    }
    let data = (try? JSONSerialization.data(withJSONObject: rules)) ?? Data("[]".utf8)
    return String(decoding: data, as: UTF8.self)
  }
}
