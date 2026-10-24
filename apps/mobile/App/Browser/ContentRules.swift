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
    "#cookie-notice", "#gdpr-cookie-message", "#sp_message_container_", "[id^='sp_message_container']",
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

  static let rejectButtons = [
    "#onetrust-reject-all-handler", "#CybotCookiebotDialogBodyButtonDecline", "#CybotCookiebotDialogBodyLevelButtonLevelOptinDeclineAll",
    "#didomi-notice-disagree-button", ".didomi-continue-without-agreeing", ".fc-cta-do-not-consent", "#truste-consent-required",
    ".osano-cm-denyAll", "#hs-eu-decline-button", ".cky-btn-reject", "#cookie-law-info-bar .cli_action_button[data-cli_action=reject]",
    ".cmplz-deny", "#sp-cc-rejectall-link", "[data-testid=uc-deny-all-button]", ".qc-cmp2-summary-buttons button[mode=secondary]",
    "button.sp_choice_type_REJECT_ALL", ".message-component.sp_choice_type_13", "#axeptio_btn_dismiss", ".iubenda-cs-reject-btn",
    "#tarteaucitronAllDenied2", ".termly-styles-deny-button", "#moove_gdpr_cookie_modal .moove-gdpr-modal-reject-all",
  ]

  static func declineCookiePrompts(allowed: [String]) -> String {
    let selectors = (try? JSONSerialization.data(withJSONObject: rejectButtons)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
    let skip = (try? JSONSerialization.data(withJSONObject: allowed)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
    return """
    (() => {
      const host = location.hostname;
      if (\(skip).some((h) => host === h || host.endsWith("." + h))) return;
      const selectors = \(selectors);
      const decline = () => {
        for (const s of selectors) {
          const button = document.querySelector(s);
          if (button) { button.click(); return true; }
        }
        return false;
      };
      if (decline()) return;
      let checks = 0;
      const watch = new MutationObserver(() => { if (decline() || ++checks > 400) watch.disconnect(); });
      watch.observe(document.documentElement, { childList: true, subtree: true });
      setTimeout(() => watch.disconnect(), 15000);
    })();
    """
  }

  static func hideEmptyAdBars(allowed: [String]) -> String {
    let skip = (try? JSONSerialization.data(withJSONObject: allowed)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
    return """
    (() => {
      const host = location.hostname;
      if (\(skip).some((h) => host === h || host.endsWith("." + h))) return;
      const media = 'img,video,iframe,canvas,svg,picture,object,embed';
      const visible = (el) => { const r = el.getBoundingClientRect(); return r.width > 4 && r.height > 4; };
      const empty = (el) => el.innerText.trim() === '' && ![...el.querySelectorAll(media)].some(visible);
      const sweep = () => {
        const h = window.innerHeight;
        for (const el of document.querySelectorAll('body *')) {
          const s = getComputedStyle(el);
          if (s.position !== 'fixed' && s.position !== 'sticky') continue;
          const r = el.getBoundingClientRect();
          if (r.height < 20 || r.height > 180 || r.bottom < h - 4 || r.width < window.innerWidth * 0.6) continue;
          if (empty(el)) el.style.setProperty('display', 'none', 'important');
        }
      };
      let timer = 0;
      const soon = () => { clearTimeout(timer); timer = setTimeout(sweep, 400); };
      soon();
      new MutationObserver(soon).observe(document.documentElement, { childList: true, subtree: true });
      setTimeout(sweep, 2500);
    })();
    """
  }
}
