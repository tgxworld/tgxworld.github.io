require "json"

class ImageProcessingReport
  def initialize(manifest_path:)
    @manifest_path = File.expand_path(manifest_path)
    @report_directory = File.dirname(@manifest_path)
    @manifest = JSON.parse(File.read(@manifest_path))
  end

  def write
    raise "The report has no image comparisons." if visual_cases.empty?

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
          <meta name="description" content="Compare ImageMagick and stock libvips output one change at a time.">
          <title>ImageMagick and stock libvips comparison</title>
          <style>
            :root {
              color-scheme: light;
              --background: #f3f5f8;
              --surface: #ffffff;
              --surface-muted: #f7f8fa;
              --border: #d9dee7;
              --text: #172033;
              --muted: #5f6878;
              --accent: #3157d5;
              --accent-dark: #2445b0;
              --pass: #087443;
              --pass-soft: #e7f7ef;
              --fail: #b42318;
              --fail-soft: #fff0ee;
              --shadow: 0 18px 45px rgb(23 32 51 / 9%);
            }

            * { box-sizing: border-box; }

            body {
              background: var(--background);
              color: var(--text);
              font: 16px/1.5 system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
              margin: 0;
            }

            button, select { font: inherit; }

            button:focus-visible,
            select:focus-visible,
            summary:focus-visible,
            a:focus-visible {
              outline: 3px solid #9aaff8;
              outline-offset: 3px;
            }

            main {
              margin: 0 auto;
              max-width: 1240px;
              padding: 32px 20px 56px;
            }

            .page-header {
              align-items: end;
              display: flex;
              gap: 24px;
              justify-content: space-between;
              margin-bottom: 22px;
            }

            .eyebrow {
              color: var(--accent-dark);
              font-size: 0.78rem;
              font-weight: 800;
              letter-spacing: 0.09em;
              margin: 0 0 8px;
              text-transform: uppercase;
            }

            h1 {
              font-size: clamp(1.8rem, 4vw, 3rem);
              letter-spacing: -0.035em;
              line-height: 1.08;
              margin: 0 0 10px;
            }

            .intro {
              color: var(--muted);
              margin: 0;
              max-width: 700px;
            }

            .overall-status {
              background: var(--pass-soft);
              border: 1px solid #8ed6b5;
              border-radius: 999px;
              color: var(--pass);
              flex: 0 0 auto;
              font-size: 0.9rem;
              font-weight: 750;
              padding: 8px 13px;
            }

            .viewer {
              background: var(--surface);
              border: 1px solid var(--border);
              border-radius: 18px;
              box-shadow: var(--shadow);
              overflow: hidden;
            }

            .viewer__top {
              border-bottom: 1px solid var(--border);
              padding: 22px 24px 20px;
            }

            .step-row {
              align-items: center;
              display: flex;
              gap: 16px;
              justify-content: space-between;
              margin-bottom: 14px;
            }

            .step-label {
              color: var(--muted);
              font-size: 0.9rem;
              font-weight: 700;
              margin: 0;
            }

            .jump-label {
              align-items: center;
              color: var(--muted);
              display: flex;
              font-size: 0.85rem;
              gap: 8px;
            }

            select {
              background: white;
              border: 1px solid var(--border);
              border-radius: 8px;
              color: var(--text);
              max-width: min(420px, 55vw);
              padding: 7px 32px 7px 10px;
            }

            progress {
              accent-color: var(--accent);
              display: block;
              height: 7px;
              width: 100%;
            }

            .title-row {
              align-items: start;
              display: flex;
              gap: 16px;
              justify-content: space-between;
              margin-top: 20px;
            }

            h2 {
              font-size: clamp(1.35rem, 3vw, 2rem);
              letter-spacing: -0.025em;
              line-height: 1.2;
              margin: 0;
            }

            .result-badge {
              border: 1px solid;
              border-radius: 999px;
              flex: 0 0 auto;
              font-size: 0.8rem;
              font-weight: 800;
              letter-spacing: 0.06em;
              padding: 6px 10px;
              text-transform: uppercase;
            }

            .result-badge--pass {
              background: var(--pass-soft);
              border-color: #8ed6b5;
              color: var(--pass);
            }

            .result-badge--fail {
              background: var(--fail-soft);
              border-color: #f2a49b;
              color: var(--fail);
            }

            .viewer__body { padding: 24px; }

            .images {
              align-items: stretch;
              display: grid;
              gap: 16px;
              grid-template-columns: repeat(4, minmax(0, 1fr));
            }

            figure {
              background: var(--surface-muted);
              border: 1px solid var(--border);
              border-radius: 12px;
              margin: 0;
              min-width: 0;
              overflow: hidden;
            }

            figcaption {
              border-bottom: 1px solid var(--border);
              font-weight: 750;
              padding: 11px 13px;
            }

            .image-frame {
              align-items: center;
              background: repeating-conic-gradient(#e7eaf0 0 25%, white 0 50%) 0 / 18px 18px;
              display: flex;
              justify-content: center;
              min-height: 240px;
              overflow: auto;
              padding: 16px;
            }

            .image-frame img {
              display: block;
              flex: 0 0 auto;
              height: auto;
              max-width: 100%;
              object-fit: contain;
              width: auto;
            }

            .image-note {
              color: var(--muted);
              font-size: 0.78rem;
              margin: 8px 0 0;
              text-align: center;
            }

            .result-summary {
              background: #f1f5ff;
              border: 1px solid #cdd8f9;
              border-radius: 12px;
              display: grid;
              gap: 8px;
              grid-template-columns: repeat(3, minmax(0, 1fr));
              margin-top: 20px;
              padding: 16px;
            }

            .result-summary p { margin: 0; }

            .result-summary strong {
              display: block;
              font-size: 0.78rem;
              letter-spacing: 0.05em;
              margin-bottom: 3px;
              text-transform: uppercase;
            }

            details {
              border-top: 1px solid var(--border);
              margin-top: 22px;
              padding-top: 18px;
            }

            summary {
              color: var(--accent-dark);
              cursor: pointer;
              font-weight: 750;
            }

            .details-grid {
              display: grid;
              gap: 10px 18px;
              grid-template-columns: max-content minmax(0, 1fr);
              margin: 16px 0 0;
            }

            .details-grid dt { color: var(--muted); }
            .details-grid dd { margin: 0; overflow-wrap: anywhere; }
            .details-grid a { color: var(--accent-dark); }

            .viewer__controls {
              align-items: center;
              background: var(--surface-muted);
              border-top: 1px solid var(--border);
              display: flex;
              gap: 16px;
              justify-content: space-between;
              padding: 16px 24px;
            }

            .nav-button {
              background: white;
              border: 1px solid #b7c2d4;
              border-radius: 9px;
              color: var(--text);
              cursor: pointer;
              font-weight: 750;
              min-width: 128px;
              padding: 10px 14px;
            }

            .nav-button--next {
              background: var(--accent);
              border-color: var(--accent);
              color: white;
            }

            .nav-button:disabled {
              cursor: not-allowed;
              opacity: 0.42;
            }

            .keyboard-note {
              color: var(--muted);
              font-size: 0.82rem;
              margin: 0;
              text-align: center;
            }

            .evidence-link {
              color: var(--muted);
              font-size: 0.85rem;
              margin: 18px 0 0;
              text-align: center;
            }

            .evidence-link a { color: var(--accent-dark); }

            .sr-only {
              height: 1px;
              margin: -1px;
              overflow: hidden;
              padding: 0;
              position: absolute;
              width: 1px;
              clip: rect(0, 0, 0, 0);
              white-space: nowrap;
            }

            @media (max-width: 840px) {
              .images { grid-template-columns: 1fr; }
              .image-frame { min-height: 180px; }
              .result-summary { grid-template-columns: 1fr; }
            }

            @media (max-width: 620px) {
              main { padding: 18px 10px 36px; }
              .page-header { align-items: start; flex-direction: column; gap: 14px; }
              .viewer { border-radius: 12px; }
              .viewer__top, .viewer__body { padding: 18px 14px; }
              .step-row { align-items: stretch; flex-direction: column; gap: 10px; }
              .jump-label { align-items: stretch; flex-direction: column; }
              select { max-width: none; width: 100%; }
              .title-row { align-items: start; flex-direction: column; }
              .viewer__controls { padding: 14px; }
              .keyboard-note { display: none; }
              .nav-button { min-width: 0; }
              .details-grid { grid-template-columns: 1fr; }
              .details-grid dd { margin-bottom: 6px; }
            }
          </style>
        </head>
        <body>
          <main>
            <header class="page-header">
              <div>
                <p class="eyebrow">Image processor change</p>
                <h1>ImageMagick and stock libvips</h1>
                <p class="intro">Review one output change at a time. The images stay at native size.</p>
              </div>
              <div class="overall-status" id="overall-status"></div>
            </header>

            <section class="viewer" aria-labelledby="case-title">
              <div class="viewer__top">
                <div class="step-row">
                  <p class="step-label" id="step-label"></p>
                  <label class="jump-label">
                    Jump to a change
                    <select id="case-select"></select>
                  </label>
                </div>
                <progress id="progress" max="1" value="0"></progress>
                <div class="title-row">
                  <h2 id="case-title"></h2>
                  <span class="result-badge" id="result-badge"></span>
                </div>
              </div>

              <div class="viewer__body">
                <div class="images">
                  <figure>
                    <figcaption>Source</figcaption>
                    <a class="image-frame" id="source-link">
                      <img id="source-image" alt="">
                    </a>
                  </figure>
                  <figure>
                    <figcaption>Before: ImageMagick</figcaption>
                    <a class="image-frame" id="before-link">
                      <img id="before-image" alt="">
                    </a>
                  </figure>
                  <figure>
                    <figcaption>After: stock libvips</figcaption>
                    <a class="image-frame" id="after-link">
                      <img id="after-image" alt="">
                    </a>
                  </figure>
                  <figure>
                    <figcaption>Pixel difference</figcaption>
                    <a class="image-frame" id="diff-link">
                      <img id="diff-image" alt="">
                    </a>
                  </figure>
                </div>
                <p class="image-note">Small images remain small. Select an image to open its source file.</p>

                <div class="result-summary" aria-label="Comparison result">
                  <p><strong>Dimensions</strong><span id="dimensions-result"></span></p>
                  <p><strong>Pixel difference</strong><span id="pixel-result"></span></p>
                  <p><strong>File size</strong><span id="size-result"></span></p>
                </div>

                <details>
                  <summary>Show technical details for this change</summary>
                  <dl class="details-grid">
                    <dt>Discourse entry point</dt><dd><code id="entrypoint"></code></dd>
                    <dt>Comparison ID</dt><dd><code id="case-id"></code></dd>
                    <dt>Allowed pixel difference</dt><dd id="threshold"></dd>
                    <dt>Source file</dt><dd id="source-file"></dd>
                    <dt>ImageMagick file</dt><dd id="before-file"></dd>
                    <dt>Stock libvips file</dt><dd id="after-file"></dd>
                    <dt>Difference file</dt><dd id="diff-file"></dd>
                  </dl>
                </details>
              </div>

              <footer class="viewer__controls">
                <button class="nav-button" id="previous" type="button">Previous change</button>
                <p class="keyboard-note">Use the left and right arrow keys to move.</p>
                <button class="nav-button nav-button--next" id="next" type="button">Next change</button>
              </footer>
            </section>

            <p class="evidence-link">Need the full test data? <a href="manifest.json">Open the evidence manifest</a>.</p>
            <p class="sr-only" id="change-announcement" aria-live="polite"></p>
          </main>

          <script id="report-data" type="application/json">#{report_json}</script>
          <script>
            (() => {
              const report = JSON.parse(document.getElementById("report-data").textContent);
              const cases = report.visualCases;
              const select = document.getElementById("case-select");
              let currentIndex = Math.max(0, cases.findIndex((item) => `#${item.id}` === window.location.hash));

              const formatBytes = (bytes) => `${new Intl.NumberFormat("en-US").format(bytes)} B`;
              const formatPercent = (value, digits = 2) => `${value.toFixed(digits)}%`;
              const dimensions = (asset) => asset.dimensions.join("×");

              const setImage = (name, asset, source, label, target = source) => {
                const image = document.getElementById(`${name}-image`);
                const link = document.getElementById(`${name}-link`);
                image.src = source;
                image.alt = `${label} for ${cases[currentIndex].label}`;
                image.width = asset.dimensions[0];
                image.height = asset.dimensions[1];
                link.href = target;
              };

              const fileLink = (path, bytes) => {
                const link = document.createElement("a");
                link.href = path;
                link.textContent = `${path} (${formatBytes(bytes)})`;
                return link;
              };

              const replaceWithLink = (id, path, bytes) => {
                const container = document.getElementById(id);
                container.replaceChildren(fileLink(path, bytes));
              };

              const render = () => {
                const item = cases[currentIndex];
                const pixelPercent = item.normalizedMeanRgbaError * 100;
                const sizeChange = (item.sizeRatio - 1) * 100;
                const sameDimensions = dimensions(item.before) === dimensions(item.after);

                document.getElementById("step-label").textContent = `Change ${currentIndex + 1} of ${cases.length}`;
                document.getElementById("progress").max = cases.length;
                document.getElementById("progress").value = currentIndex + 1;
                document.getElementById("case-title").textContent = item.label;
                document.getElementById("case-id").textContent = item.id;
                document.getElementById("entrypoint").textContent = item.entrypoint;
                document.getElementById("threshold").textContent = formatPercent(item.threshold * 100);
                document.getElementById("dimensions-result").textContent = sameDimensions
                  ? `Both outputs are ${dimensions(item.before)}.`
                  : `ImageMagick is ${dimensions(item.before)}. Stock libvips is ${dimensions(item.after)}.`;
                document.getElementById("pixel-result").textContent = pixelPercent === 0
                  ? "The decoded pixels match exactly."
                  : `The average channel difference is ${formatPercent(pixelPercent, 3)}.`;
                document.getElementById("size-result").textContent = Math.abs(sizeChange) < 0.5
                  ? "The file sizes are almost equal."
                  : `The stock libvips file is ${formatPercent(Math.abs(sizeChange), 1)} ${sizeChange < 0 ? "smaller" : "larger"}.`;

                const badge = document.getElementById("result-badge");
                badge.textContent = item.passed ? "Pass" : "Fail";
                badge.className = `result-badge result-badge--${item.passed ? "pass" : "fail"}`;

                setImage("source", item.source, item.source.viewPath, "Source image", item.source.path);
                setImage("before", item.before, item.before.viewPath, "ImageMagick output", item.before.path);
                setImage("after", item.after, item.after.viewPath, "Stock libvips output", item.after.path);
                setImage("diff", item.before, item.diffPath, "Pixel difference");
                replaceWithLink("source-file", item.source.path, item.source.bytes);
                replaceWithLink("before-file", item.before.path, item.before.bytes);
                replaceWithLink("after-file", item.after.path, item.after.bytes);
                replaceWithLink("diff-file", item.diffPath, item.diffBytes);

                document.getElementById("previous").disabled = currentIndex === 0;
                document.getElementById("next").disabled = currentIndex === cases.length - 1;
                select.value = String(currentIndex);
                window.history.replaceState(null, "", `#${item.id}`);
                document.getElementById("change-announcement").textContent = `Change ${currentIndex + 1}: ${item.label}`;
              };

              cases.forEach((item, index) => {
                const option = document.createElement("option");
                option.value = String(index);
                option.textContent = `${index + 1}. ${item.label}`;
                select.append(option);
              });

              document.getElementById("overall-status").textContent = `${report.passedCount} of ${report.totalCount} comparisons pass`;
              document.getElementById("previous").addEventListener("click", () => {
                currentIndex = Math.max(0, currentIndex - 1);
                render();
              });
              document.getElementById("next").addEventListener("click", () => {
                currentIndex = Math.min(cases.length - 1, currentIndex + 1);
                render();
              });
              select.addEventListener("change", () => {
                currentIndex = Number(select.value);
                render();
              });
              window.addEventListener("keydown", (event) => {
                if (event.target.matches("select, button, summary, a")) return;
                if (event.key === "ArrowLeft" && currentIndex > 0) {
                  currentIndex -= 1;
                  render();
                }
                if (event.key === "ArrowRight" && currentIndex < cases.length - 1) {
                  currentIndex += 1;
                  render();
                }
              });

              render();
            })();
          </script>
        </body>
      </html>
    HTML
  end

  def report_json
    data = {
      totalCount: visual_cases.length,
      passedCount: visual_cases.count { |item| item["passed"] },
      visualCases:
        visual_cases.map do |item|
          before = asset_data(item.fetch("before"))
          after = asset_data(item.fetch("after"))
          source = asset_data(item.fetch("source"))
          diff_path = item.fetch("diff_path")
          {
            id: item.fetch("id"),
            label: item.fetch("label"),
            entrypoint: item.fetch("entrypoint"),
            threshold: item.fetch("threshold"),
            normalizedMeanRgbaError: item.fetch("normalized_mean_rgba_error"),
            sizeRatio: item.fetch("size_ratio"),
            passed: item.fetch("passed"),
            source:,
            before:,
            after:,
            diffPath: diff_path,
            diffBytes: File.size(File.join(@report_directory, diff_path))
          }
        end
    }

    JSON.generate(data).gsub("<", "\\u003c")
  end

  def visual_cases
    Array(@manifest["visual_cases"])
  end

  def asset_data(asset)
    {
      path: asset.fetch("path"),
      viewPath: asset.fetch("view_path", asset.fetch("path")),
      dimensions: asset.fetch("dimensions"),
      bytes: asset.fetch("bytes")
    }
  end
end

manifest_path =
  ARGV.fetch(0) { raise ArgumentError, "Specify the path to manifest.json." }
ImageProcessingReport.new(manifest_path:).write
