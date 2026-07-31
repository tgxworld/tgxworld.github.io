require "cgi"
require "digest"
require "json"
require "pathname"

class ImageProcessingReport
  def initialize(manifest_path:)
    @manifest_path = File.expand_path(manifest_path)
    @report_directory = File.dirname(@manifest_path)
    @manifest = JSON.parse(File.read(@manifest_path))
  end

  def write
    File.write(File.join(@report_directory, "index.html"), html)
  end

  private

  def html
    <<~HTML
      <!doctype html>
      <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>#{h(title)}</title>
          <style>
            :root {
              color-scheme: light;
              --background: #f5f7fb;
              --surface: #ffffff;
              --surface-muted: #eef2f7;
              --border: #d8dee9;
              --text: #172033;
              --muted: #5c667a;
              --pass: #087443;
              --pass-soft: #e7f7ef;
              --fail: #b42318;
              --fail-soft: #fff0ee;
              --accent: #3157d5;
              --code: #222a3a;
            }
            * { box-sizing: border-box; }
            html { scroll-behavior: smooth; }
            body {
              background: var(--background);
              color: var(--text);
              font: 15px/1.55 system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
              margin: 0;
            }
            a { color: var(--accent); }
            a:focus-visible, button:focus-visible { outline: 3px solid #8aa2ff; outline-offset: 2px; }
            main { margin: 0 auto; max-width: 1540px; padding: 32px 24px 64px; }
            h1, h2, h3, h4 { line-height: 1.2; }
            h1 { font-size: clamp(2rem, 5vw, 3.75rem); letter-spacing: -0.04em; margin: 0 0 12px; max-width: 1100px; }
            h2 { font-size: 1.65rem; letter-spacing: -0.02em; margin: 0 0 16px; }
            h3 { font-size: 1.15rem; margin: 0; }
            p { margin: 0 0 12px; }
            code, pre {
              background: var(--code);
              border-radius: 5px;
              color: #f5f7fa;
              font: 0.86rem/1.5 ui-monospace, SFMono-Regular, Consolas, monospace;
              overflow-wrap: anywhere;
            }
            code { padding: 2px 5px; }
            pre { margin: 8px 0 0; overflow-x: auto; padding: 12px; white-space: pre-wrap; }
            .hero {
              background: linear-gradient(135deg, #172033, #293958);
              border-radius: 18px;
              color: white;
              margin-bottom: 24px;
              overflow: hidden;
              padding: clamp(24px, 5vw, 52px);
            }
            .hero__meta { color: #cdd6e8; margin-bottom: 20px; }
            .hero__summary { color: #e5eaf4; font-size: 1.05rem; max-width: 980px; }
            .status {
              align-items: center;
              border: 1px solid;
              border-radius: 999px;
              display: inline-flex;
              font-size: 0.78rem;
              font-weight: 750;
              gap: 7px;
              letter-spacing: 0.08em;
              padding: 6px 11px;
              text-transform: uppercase;
            }
            .status--pass { background: var(--pass-soft); border-color: #8ed6b5; color: var(--pass); }
            .status--fail { background: var(--fail-soft); border-color: #f2a49b; color: var(--fail); }
            .status--unknown { background: var(--surface-muted); border-color: var(--border); color: var(--muted); }
            .hero .status { margin-bottom: 18px; }
            .downloads { display: flex; flex-wrap: wrap; gap: 10px; margin-top: 22px; }
            .downloads a {
              background: white;
              border-radius: 8px;
              color: #172033;
              font-weight: 700;
              padding: 9px 13px;
              text-decoration: none;
            }
            .downloads a:hover { text-decoration: underline; }
            .section {
              background: var(--surface);
              border: 1px solid var(--border);
              border-radius: 14px;
              margin-top: 20px;
              padding: clamp(18px, 3vw, 30px);
            }
            .section__intro { color: var(--muted); max-width: 980px; }
            .overview-grid {
              display: grid;
              gap: 16px;
              grid-template-columns: repeat(auto-fit, minmax(min(100%, 320px), 1fr));
            }
            .data-card {
              background: var(--surface-muted);
              border-radius: 10px;
              min-width: 0;
              padding: 18px;
            }
            .data-card h3 { margin-bottom: 12px; }
            .key-values { display: grid; gap: 8px 14px; grid-template-columns: minmax(130px, max-content) minmax(0, 1fr); margin: 0; }
            .key-values dt { color: var(--muted); font-weight: 650; }
            .key-values dd { margin: 0; min-width: 0; overflow-wrap: anywhere; }
            .key-values .key-values { grid-column: 1 / -1; margin: 6px 0 6px 14px; }
            .value-list { margin: 4px 0 0; padding-left: 20px; }
            .table-wrap { overflow-x: auto; }
            table { border-collapse: collapse; min-width: 800px; width: 100%; }
            th, td { border-bottom: 1px solid var(--border); padding: 10px 12px; text-align: left; vertical-align: top; }
            th { background: var(--surface-muted); color: #3f4a5e; font-size: 0.78rem; letter-spacing: 0.04em; text-transform: uppercase; }
            tbody tr:last-child td { border-bottom: 0; }
            td code { display: inline-block; max-width: 560px; }
            .result-cell { white-space: nowrap; }
            .visual-list { display: grid; gap: 20px; }
            .visual-case {
              border: 1px solid var(--border);
              border-radius: 12px;
              overflow: hidden;
            }
            .visual-case--fail { border-color: #ee9a91; }
            .visual-case__header {
              align-items: flex-start;
              background: var(--surface-muted);
              display: flex;
              flex-wrap: wrap;
              gap: 12px;
              justify-content: space-between;
              padding: 16px 18px;
            }
            .visual-case__header p { color: var(--muted); margin: 5px 0 0; }
            .metrics {
              display: flex;
              flex-wrap: wrap;
              gap: 8px;
              margin-top: 12px;
            }
            .metric {
              background: white;
              border: 1px solid var(--border);
              border-radius: 7px;
              padding: 6px 9px;
            }
            .visual-case__body { padding: 18px; }
            .images {
              align-items: start;
              display: grid;
              gap: 18px;
              grid-template-columns: repeat(auto-fit, minmax(min(100%, 300px), 1fr));
            }
            figure { margin: 0; min-width: 0; overflow: auto; }
            figcaption { font-weight: 750; margin-bottom: 8px; }
            figure img {
              background: repeating-conic-gradient(#e8ebf0 0 25%, white 0 50%) 0 / 20px 20px;
              border: 1px solid var(--border);
              display: block;
              height: auto;
              max-width: 100%;
              object-fit: contain;
              width: auto;
            }
            .asset-table { margin-top: 18px; }
            .asset-table table { font-size: 0.85rem; min-width: 900px; }
            .sha { font-family: ui-monospace, SFMono-Regular, Consolas, monospace; overflow-wrap: anywhere; }
            .findings { display: grid; gap: 16px; grid-template-columns: repeat(auto-fit, minmax(min(100%, 360px), 1fr)); }
            .finding {
              border: 1px solid var(--border);
              border-radius: 10px;
              min-width: 0;
              padding: 16px;
            }
            .finding__header { align-items: center; display: flex; gap: 10px; justify-content: space-between; margin-bottom: 10px; }
            .finding__group { color: var(--muted); font-size: 0.78rem; font-weight: 700; letter-spacing: 0.06em; margin-bottom: 4px; text-transform: uppercase; }
            .notes { margin-bottom: 0; }
            .empty { color: var(--muted); font-style: italic; }
            .filters { align-items: center; display: flex; flex-wrap: wrap; gap: 10px; margin: 0 0 16px; }
            button {
              background: white;
              border: 1px solid var(--border);
              border-radius: 7px;
              color: var(--text);
              cursor: pointer;
              font: inherit;
              font-weight: 650;
              padding: 7px 10px;
            }
            button[aria-pressed="true"] { background: #dfe7ff; border-color: #9cb0ef; }
            [hidden] { display: none !important; }
            @media (max-width: 640px) {
              main { padding: 14px 10px 40px; }
              .hero, .section { border-radius: 10px; }
              .key-values { grid-template-columns: 1fr; }
              .key-values dd { margin-bottom: 5px; }
            }
          </style>
        </head>
        <body>
          <main>
            #{hero_html}
            #{methodology_html}
            #{contracts_html}
            #{visual_cases_html}
            #{findings_html}
            #{notes_html}
          </main>
          <script>
            (() => {
              document.querySelectorAll("[data-filter]").forEach((button) => {
                button.addEventListener("click", () => {
                  const container = button.closest("[data-filter-container]");
                  const filter = button.dataset.filter;
                  container.querySelectorAll("[data-filter]").forEach((candidate) => {
                    candidate.setAttribute("aria-pressed", String(candidate === button));
                  });
                  container.querySelectorAll("[data-filter-result]").forEach((result) => {
                    result.hidden = filter === "failed" && result.dataset.passed === "true";
                  });
                });
              });
            })();
          </script>
        </body>
      </html>
    HTML
  end

  def title
    @manifest["title"].to_s.empty? ? "Discourse image-processing parity evidence" : @manifest["title"]
  end

  def overall_pass
    return @manifest["overall_pass"] unless @manifest["overall_pass"].nil?

    results = contracts.map { |contract| contract["passed"] }.compact
    results += visual_cases.map { |visual_case| visual_case["passed"] }.compact
    results += findings.map { |finding| finding["passed"] }.compact
    results.empty? ? nil : results.all?
  end

  def hero_html
    generated_at = @manifest["generated_at"]
    summary = @manifest["summary"]
    meta = generated_at.to_s.empty? ? "" : "<p class=\"hero__meta\">Generated #{h(generated_at)}</p>"
    summary_html = summary.to_s.empty? ? "" : "<p class=\"hero__summary\">#{h(summary)}</p>"
    <<~HTML
      <header class="hero">
        #{status_badge(overall_pass)}
        <h1>#{h(title)}</h1>
        #{meta}
        #{summary_html}
        <nav class="downloads" aria-label="Evidence downloads">
          <a href="manifest.json" download>Download manifest.json</a>
          <a href="artifacts.sha256" download>Download artifacts.sha256</a>
        </nav>
      </header>
    HTML
  end

  def methodology_html
    cards = [
      ["Provenance and commands", @manifest["provenance"]],
      ["Fixed settings", @manifest["settings"]],
      ["Acceptance thresholds", @manifest["thresholds"]],
    ]
    populated_cards =
      cards.filter_map do |heading, value|
        next if blank_value?(value)

        <<~HTML
          <article class="data-card">
            <h3>#{h(heading)}</h3>
            #{render_value(value)}
          </article>
        HTML
      end
    methodology = @manifest["methodology"]
    methodology_copy =
      if blank_value?(methodology)
        "Both processors were exercised through the same Discourse Rails/domain entrypoints. Every visual contract compares equal-sized decoded RGBA outputs and records exact artifact metadata."
      else
        methodology
      end
    <<~HTML
      <section class="section" id="methodology">
        <h2>Methodology and provenance</h2>
        <p class="section__intro">#{h(methodology_copy)}</p>
        <div class="overview-grid">
          #{populated_cards.join}
        </div>
      </section>
    HTML
  end

  def contracts
    Array(@manifest["contracts"])
  end

  def contracts_html
    rows =
      contracts.map do |contract|
        <<~HTML
          <tr data-filter-result data-passed="#{contract["passed"] == true}">
            <td>#{h(contract["group"])}</td>
            <td><code>#{h(contract["id"])}</code></td>
            <td>#{h(contract["description"])}</td>
            <td>#{render_compact_value(contract["expected"])}</td>
            <td>#{render_compact_value(contract["actual"])}</td>
            <td class="result-cell">#{status_badge(contract["passed"])}</td>
          </tr>
        HTML
      end.join
    body = rows.empty? ? "<p class=\"empty\">No textual contracts were recorded.</p>" : <<~HTML
      <div class="filters">
        <button type="button" data-filter="all" aria-pressed="true">All contracts</button>
        <button type="button" data-filter="failed" aria-pressed="false">Failures only</button>
      </div>
      <div class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Group</th>
              <th>ID</th>
              <th>Contract</th>
              <th>Expected</th>
              <th>Actual</th>
              <th>Result</th>
            </tr>
          </thead>
          <tbody>#{rows}</tbody>
        </table>
      </div>
    HTML
    <<~HTML
      <section class="section" id="contracts" data-filter-container>
        <h2>Textual pass/fail contracts</h2>
        <p class="section__intro">The expected and observed behavior is retained verbatim from the evidence manifest.</p>
        #{body}
      </section>
    HTML
  end

  def visual_cases
    Array(@manifest["visual_cases"])
  end

  def visual_cases_html
    cards = visual_cases.map { |visual_case| visual_case_html(visual_case) }.join
    body = cards.empty? ? "<p class=\"empty\">No visual comparisons were recorded.</p>" : <<~HTML
      <div class="filters">
        <button type="button" data-filter="all" aria-pressed="true">All visual cases</button>
        <button type="button" data-filter="failed" aria-pressed="false">Failures only</button>
      </div>
      <div class="visual-list">#{cards}</div>
    HTML
    <<~HTML
      <section class="section" id="visual-cases" data-filter-container>
        <h2>Native-size visual comparisons</h2>
        <p class="section__intro">
          Images are shown at intrinsic size and are never magnified. They may shrink to fit a narrow viewport.
          The diff is generated from the decoded RGBA pixels used by the numerical comparison.
        </p>
        #{body}
      </section>
    HTML
  end

  def visual_case_html(visual_case)
    before = visual_case["before"] || {}
    after = visual_case["after"] || {}
    diff = {
      "processor" => "RGBA difference",
      "path" => visual_case["diff_path"],
      "view_path" => visual_case["diff_path"],
      "dimensions" => before["dimensions"] || after["dimensions"],
      "format" => "PNG",
      "bytes" => file_bytes(visual_case["diff_path"]),
      "sha256" => visual_case["diff_sha256"] || file_sha256(visual_case["diff_path"]),
    }
    passed = visual_case["passed"]
    css_class = passed == false ? " visual-case--fail" : ""
    <<~HTML
      <article class="visual-case#{css_class}" data-filter-result data-passed="#{passed == true}" id="visual-#{anchor(visual_case["id"])}">
        <header class="visual-case__header">
          <div>
            <h3>#{h(visual_case["label"] || visual_case["id"])}</h3>
            <p><code>#{h(visual_case["id"])}</code> via #{h(visual_case["entrypoint"])}</p>
            <div class="metrics">
              <span class="metric">RGBA error: <strong>#{number(visual_case["normalized_mean_rgba_error"])}</strong></span>
              <span class="metric">Threshold: <strong>#{number(visual_case["threshold"])}</strong></span>
              <span class="metric">Vips/IM size ratio: <strong>#{number(visual_case["size_ratio"])}</strong></span>
            </div>
          </div>
          #{status_badge(passed)}
        </header>
        <div class="visual-case__body">
          <div class="images">
            #{figure_html(asset: before, fallback_label: "ImageMagick")}
            #{figure_html(asset: after, fallback_label: "Vips")}
            #{figure_html(asset: diff, fallback_label: "RGBA difference")}
          </div>
          #{asset_table_html(before: before, after: after, diff: diff)}
        </div>
      </article>
    HTML
  end

  def figure_html(asset:, fallback_label:)
    source = local_asset_url(asset["view_path"] || asset["path"])
    label = asset["processor"].to_s.empty? ? fallback_label : asset["processor"]
    return "<figure><figcaption>#{h(label)}</figcaption><p class=\"empty\">No view asset recorded.</p></figure>" unless source

    dimensions = dimensions_value(asset["dimensions"])
    width, height = dimensions.is_a?(Array) ? dimensions : [nil, nil]
    size_attributes =
      if width && height
        " width=\"#{h(width)}\" height=\"#{h(height)}\""
      else
        ""
      end
    <<~HTML
      <figure>
        <figcaption>#{h(label)}</figcaption>
        <a href="#{h(source)}">
          <img src="#{h(source)}"#{size_attributes} alt="#{h(label)} output for this comparison" loading="lazy">
        </a>
      </figure>
    HTML
  end

  def asset_table_html(before:, after:, diff:)
    rows =
      [[before, "ImageMagick"], [after, "Vips"], [diff, "RGBA difference"]].map do |asset, fallback_label|
        processor = asset["processor"].to_s.empty? ? fallback_label : asset["processor"]
        path = asset["path"] || asset["view_path"]
        <<~HTML
          <tr>
            <td>#{h(processor)}</td>
            <td>#{h(format_dimensions(asset["dimensions"]))}</td>
            <td>#{h(asset["format"])}</td>
            <td>#{h(exact_bytes(asset["bytes"]))}</td>
            <td class="sha">#{h(asset["sha256"])}</td>
            <td>#{path_link(path)}</td>
          </tr>
        HTML
      end.join
    <<~HTML
      <div class="table-wrap asset-table">
        <table>
          <thead>
            <tr>
              <th>Artifact</th>
              <th>Dimensions</th>
              <th>Format</th>
              <th>File size</th>
              <th>SHA-256</th>
              <th>File</th>
            </tr>
          </thead>
          <tbody>#{rows}</tbody>
        </table>
      </div>
    HTML
  end

  def findings
    Array(@manifest["findings"])
  end

  def findings_html
    cards =
      findings.map do |finding|
        <<~HTML
          <article class="finding">
            <p class="finding__group">#{h(finding["group"])}</p>
            <div class="finding__header">
              <h3>#{h(finding["label"] || finding["id"])}</h3>
              #{status_badge(finding["passed"])}
            </div>
            #{render_value(finding["details"])}
          </article>
        HTML
      end.join
    body = cards.empty? ? "<p class=\"empty\">No non-visual findings were recorded.</p>" : "<div class=\"findings\">#{cards}</div>"
    <<~HTML
      <section class="section" id="findings">
        <h2>Behavioral findings</h2>
        <p class="section__intro">
          Animation and frame classification, SVG dimensions, JPEG quality selection, format eligibility,
          metadata handling, and the deliberate Vips-enabled ICO failure are reported here.
        </p>
        #{body}
      </section>
    HTML
  end

  def notes_html
    notes = Array(@manifest["notes"])
    return "" if notes.empty?

    items = notes.map { |note| "<li>#{h(note)}</li>" }.join
    <<~HTML
      <section class="section" id="notes">
        <h2>Notes</h2>
        <ul class="notes">#{items}</ul>
      </section>
    HTML
  end

  def render_value(value)
    case value
    when Hash
      pairs =
        value.map do |key, nested_value|
          "<dt>#{h(humanize(key))}</dt><dd>#{render_value(nested_value)}</dd>"
        end.join
      "<dl class=\"key-values\">#{pairs}</dl>"
    when Array
      return "<span class=\"empty\">None</span>" if value.empty?

      "<ul class=\"value-list\">#{value.map { |item| "<li>#{render_value(item)}</li>" }.join}</ul>"
    when nil
      "<span class=\"empty\">Not recorded</span>"
    else
      text = value.to_s
      text.include?("\n") ? "<pre>#{h(text)}</pre>" : h(text)
    end
  end

  def render_compact_value(value)
    return "<span class=\"empty\">Not recorded</span>" if value.nil?

    value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false ? h(value) : render_value(value)
  end

  def status_badge(passed)
    case passed
    when true
      "<span class=\"status status--pass\">Pass</span>"
    when false
      "<span class=\"status status--fail\">Fail</span>"
    else
      "<span class=\"status status--unknown\">Not recorded</span>"
    end
  end

  def blank_value?(value)
    value.nil? || value.respond_to?(:empty?) && value.empty?
  end

  def number(value)
    return "Not recorded" if value.nil?
    return format("%.6f", value) if value.is_a?(Float)

    h(value)
  end

  def dimensions_value(value)
    return value if value.is_a?(Array) && value.length >= 2
    return [value["width"], value["height"]] if value.is_a?(Hash)

    value
  end

  def format_dimensions(value)
    dimensions = dimensions_value(value)
    return dimensions.first(2).map(&:to_s).join("×") if dimensions.is_a?(Array)
    return "Not recorded" if dimensions.nil?

    dimensions.to_s
  end

  def exact_bytes(value)
    return "Not recorded" if value.nil?

    "#{value.to_i.to_s.reverse.gsub(/(\\d{3})(?=\\d)/, '\\1,').reverse} B"
  end

  def file_bytes(path)
    relative_path = local_path(path)
    relative_path && File.file?(relative_path) ? File.size(relative_path) : nil
  end

  def file_sha256(path)
    relative_path = local_path(path)
    relative_path && File.file?(relative_path) ? Digest::SHA256.file(relative_path).hexdigest : nil
  end

  def path_link(path)
    source = local_asset_url(path)
    return "<span class=\"empty\">Not recorded</span>" unless source

    "<a href=\"#{h(source)}\">#{h(path)}</a>"
  end

  def local_asset_url(path)
    local = local_path(path)
    return nil unless local

    relative = Pathname.new(local).relative_path_from(Pathname.new(@report_directory)).to_s
    relative.split("/").map { |segment| CGI.escape(segment).gsub("+", "%20") }.join("/")
  end

  def local_path(path)
    return nil if path.to_s.empty?

    candidate = Pathname.new(path.to_s)
    absolute = candidate.absolute? ? candidate.cleanpath : Pathname.new(@report_directory).join(candidate).cleanpath
    report_root = Pathname.new(@report_directory).cleanpath
    relative = absolute.relative_path_from(report_root)
    raise "asset path escapes report directory: #{path}" if relative.each_filename.first == ".."

    absolute.to_s
  end

  def anchor(value)
    cleaned = value.to_s.downcase.gsub(/[^a-z0-9_-]+/, "-").gsub(/\A-+|-+\z/, "")
    cleaned.empty? ? "case" : cleaned
  end

  def humanize(value)
    value.to_s.tr("_", " ").split.map(&:capitalize).join(" ")
  end

  def h(value)
    CGI.escapeHTML(value.to_s)
  end
end

manifest_path = ARGV.fetch(0) { raise ArgumentError, "usage: ruby build_image_processing_report.rb /path/to/manifest.json" }
ImageProcessingReport.new(manifest_path: manifest_path).write
