import SwiftUI
import WebKit

struct ReaderArticle: Identifiable, Equatable {
  let id = UUID()
  let title: String
  let byline: String
  let site: String
  let html: String
  let baseURL: URL?
  let words: Int

  var minutes: Int { max(1, Int((Double(words) / 230).rounded())) }
}

enum ReaderExtractor {
  static let script = """
  (() => {
    const drop = 'script,style,noscript,iframe,form,nav,header,footer,aside,button,svg,canvas,video,audio,select,input,textarea,[role=navigation],[role=banner],[role=complementary],[role=dialog],[aria-hidden=true],[hidden]';
    const noisy = /comment|share|social|related|promo|advert|sponsor|newsletter|subscribe|sidebar|footer|cookie|banner|popup|modal|breadcrumb|outbrain|taboola/i;
    const doc = document.cloneNode(true);
    doc.querySelectorAll(drop).forEach((e) => e.remove());
    doc.querySelectorAll('[class],[id]').forEach((e) => {
      const tag = (e.className && e.className.toString ? e.className.toString() : '') + ' ' + (e.id || '');
      if (noisy.test(tag) && e.tagName !== 'BODY' && e.tagName !== 'ARTICLE' && e.tagName !== 'MAIN') e.remove();
    });
    const scores = new Map();
    const add = (el, n) => { if (el) scores.set(el, (scores.get(el) || 0) + n); };
    doc.querySelectorAll('p, pre, blockquote, li').forEach((p) => {
      const text = p.textContent.trim();
      if (text.length < 40) return;
      const score = 1 + Math.min(text.length / 100, 3) + (text.split(',').length - 1) * 0.3;
      add(p.parentElement, score);
      add(p.parentElement && p.parentElement.parentElement, score / 2);
    });
    let best = null, top = 0;
    scores.forEach((s, el) => {
      const links = [...el.querySelectorAll('a')].reduce((n, a) => n + a.textContent.length, 0);
      const density = 1 - Math.min(links / Math.max(el.textContent.length, 1), 1);
      const value = s * density;
      if (value > top) { top = value; best = el; }
    });
    if (!best) return null;
    const keep = new Set(['P','H1','H2','H3','H4','H5','UL','OL','LI','BLOCKQUOTE','PRE','CODE','EM','STRONG','B','I','A','IMG','FIGURE','FIGCAPTION','BR','HR','TABLE','THEAD','TBODY','TR','TD','TH','SUP','SUB']);
    const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    const abs = (u) => { try { return new URL(u, location.href).href; } catch { return ''; } };
    const clean = (node) => {
      if (node.nodeType === 3) return esc(node.textContent);
      if (node.nodeType !== 1) return '';
      const inner = [...node.childNodes].map(clean).join('');
      const tag = node.tagName;
      if (!keep.has(tag)) return inner;
      if (tag === 'IMG') {
        const src = abs(node.getAttribute('src') || node.getAttribute('data-src') || '');
        return src.startsWith('http') ? `<img src="${esc(src)}" alt="${esc(node.getAttribute('alt') || '')}">` : '';
      }
      if (tag === 'A') {
        const href = abs(node.getAttribute('href') || '');
        return href.startsWith('http') ? `<a href="${esc(href)}">${inner}</a>` : inner;
      }
      if (tag === 'BR' || tag === 'HR') return `<${tag.toLowerCase()}>`;
      return `<${tag.toLowerCase()}>${inner}</${tag.toLowerCase()}>`;
    };
    const meta = (name) => { const m = document.querySelector(`meta[property="${name}"],meta[name="${name}"]`); return m ? m.getAttribute('content') || '' : ''; };
    const h1 = document.querySelector('h1');
    const title = meta('og:title') || (h1 ? h1.textContent.trim() : '') || document.title;
    const text = best.textContent.replace(/\\s+/g, ' ').trim();
    return { title, byline: meta('author'), site: meta('og:site_name') || location.hostname.replace(/^www\\./, ''), html: clean(best), words: text.split(' ').length };
  })()
  """

  @MainActor
  static func extract(from webView: WKWebView) async -> ReaderArticle? {
    guard let result = try? await webView.evaluateJavaScript(script) as? [String: Any],
          let html = result["html"] as? String, let words = result["words"] as? Int, words >= 120 else { return nil }
    return ReaderArticle(
      title: result["title"] as? String ?? "",
      byline: result["byline"] as? String ?? "",
      site: result["site"] as? String ?? "",
      html: html,
      baseURL: webView.url,
      words: words
    )
  }
}

enum ReaderTheme: String, CaseIterable, Identifiable {
  case dark, sepia, light

  var id: String { rawValue }
  var background: String { self == .dark ? "#1C1C1E" : self == .sepia ? "#F4ECD8" : "#FFFFFF" }
  var text: String { self == .dark ? "#E5E5E7" : self == .sepia ? "#3B2F20" : "#1C1C1E" }
  var link: String { self == .dark ? "#9AB8FF" : "#2B5FD9" }
}

struct ReaderView: View {
  let article: ReaderArticle
  let close: () -> Void
  let openLink: (URL) -> Void
  @AppStorage("readerFontSize") private var fontSize = 19.0
  @AppStorage("readerSerif") private var serif = true
  @AppStorage("readerTheme") private var theme = ReaderTheme.dark.rawValue

  private var palette: ReaderTheme { ReaderTheme(rawValue: theme) ?? .dark }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 14) {
        Button("Done", action: close).fontWeight(.semibold)
        Spacer()
        Text("\(article.minutes) min read").font(.footnote).foregroundStyle(.secondary)
        Spacer()
        Menu {
          Picker("Theme", selection: $theme) {
            Text("Dark").tag(ReaderTheme.dark.rawValue)
            Text("Sepia").tag(ReaderTheme.sepia.rawValue)
            Text("Light").tag(ReaderTheme.light.rawValue)
          }
          Toggle("Serif Font", isOn: $serif)
        } label: {
          Image(systemName: "paintpalette")
        }
        Button { fontSize = max(14, fontSize - 1) } label: { Image(systemName: "textformat.size.smaller") }
        Button { fontSize = min(30, fontSize + 1) } label: { Image(systemName: "textformat.size.larger") }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 14)
      ReaderWebView(html: document, openLink: openLink)
        .ignoresSafeArea(edges: .bottom)
    }
    .background(Color(hex: palette.background).ignoresSafeArea())
    .preferredColorScheme(palette == .dark ? .dark : .light)
  }

  private var document: String {
    let font = serif ? "'New York', ui-serif, Georgia, serif" : "-apple-system, system-ui, sans-serif"
    let esc = { (s: String) in s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;") }
    return """
    <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
    body { background: \(palette.background); color: \(palette.text); font: \(Int(fontSize))px/1.6 \(font); margin: 0; padding: 8px 22px 80px; -webkit-text-size-adjust: none; }
    h1.title { font-size: 1.55em; line-height: 1.2; margin: 0.3em 0 0.2em; }
    .meta { font: 14px -apple-system, sans-serif; opacity: 0.6; margin-bottom: 1.6em; }
    img { max-width: 100%; height: auto; border-radius: 10px; }
    a { color: \(palette.link); text-decoration: none; }
    pre, code { font: 0.85em ui-monospace, Menlo, monospace; white-space: pre-wrap; }
    blockquote { margin: 1em 0; padding-left: 1em; border-left: 3px solid \(palette.text)33; opacity: 0.85; }
    table { border-collapse: collapse; width: 100%; font-size: 0.85em; } td, th { border: 1px solid \(palette.text)22; padding: 4px 6px; }
    </style></head><body>
    <div class="meta">\(esc(article.site))\(article.byline.isEmpty ? "" : " · " + esc(article.byline))</div>
    <h1 class="title">\(esc(article.title))</h1>
    \(article.html)
    </body></html>
    """
  }
}

struct ReaderWebView: UIViewRepresentable {
  let html: String
  let openLink: (URL) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(openLink: openLink) }

  func makeUIView(context: Context) -> WKWebView {
    let config = WKWebViewConfiguration()
    config.defaultWebpagePreferences.allowsContentJavaScript = false
    config.websiteDataStore = .nonPersistent()
    let web = WKWebView(frame: .zero, configuration: config)
    web.isOpaque = false
    web.backgroundColor = .clear
    web.navigationDelegate = context.coordinator
    return web
  }

  func updateUIView(_ web: WKWebView, context: Context) {
    guard context.coordinator.shown != html else { return }
    context.coordinator.shown = html
    web.loadHTMLString(html, baseURL: nil)
  }

  final class Coordinator: NSObject, WKNavigationDelegate {
    var shown = ""
    let openLink: (URL) -> Void
    init(openLink: @escaping (URL) -> Void) { self.openLink = openLink }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
      if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
        await MainActor.run { openLink(url) }
        return .cancel
      }
      return .allow
    }
  }
}
