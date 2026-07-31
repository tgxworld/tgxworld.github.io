require "chunky_png"
require "digest"
require "fileutils"
require "json"
require "open3"

RSpec.describe "image processing parity evidence" do
  fab!(:evidence_user) { Fabricate(:user, refresh_auto_groups: true) }

  def evidence_root
    ENV.fetch("EVIDENCE_DIR")
  end

  def fixture_path(filename)
    Rails.root.join("spec/fixtures/images", filename).to_s
  end

  def relative_path(path)
    Pathname(path).relative_path_from(Pathname(evidence_root)).to_s
  end

  def processor_name(use_vips)
    use_vips ? "Stock libvips" : "ImageMagick"
  end

  def fresh_input(path, extension = File.extname(path))
    tempfile = Tempfile.new(["evidence-input", extension])
    FileUtils.cp(path, tempfile.path)
    tempfile.rewind
    tempfile
  end

  def run_command(*arguments)
    stdout, stderr, status = Open3.capture3(*arguments)
    raise "#{arguments.join(" ")} failed: #{stderr}" unless status.success?
    stdout
  end

  def image_info(path, processor, view_path)
    {
      processor:,
      path: relative_path(path),
      view_path: relative_path(view_path),
      dimensions: FastImage.size(path),
      format: FastImage.type(path).to_s,
      bytes: File.size(path),
      sha256: Digest::SHA256.file(path).hexdigest,
    }
  end

  def add_contract(id:, group:, description:, expected:, actual:, passed:)
    @contracts << {
      id:,
      group:,
      description:,
      expected:,
      actual:,
      passed: !!passed,
    }
  end

  def add_finding(id:, group:, label:, details:, passed:)
    @findings << { id:, group:, label:, details:, passed: !!passed }
  end

  def metadata_presence(path)
    %w[exif-data xmp-data iptc-data icc-profile-data].to_h do |field|
      present = Vips.run("vipsheader", "--field", field, path, read: [path]).present?
      [field, present]
    rescue Discourse::Utils::CommandError
      [field, false]
    end
  end

  def frame_count(path)
    Vips.run(
      "vipsheader",
      "--field",
      "n-pages",
      path,
      read: [path],
      timeout: Upload::MAX_IDENTIFY_SECONDS,
    ).to_i
  rescue Discourse::Utils::CommandError
    1
  end

  def orientation(path)
    Vips.run("vipsheader", "--field", "orientation", path, read: [path]).to_i
  rescue Discourse::Utils::CommandError
    1
  end

  def add_visual_case(
    id:,
    label:,
    entrypoint:,
    image_magick_path:,
    vips_path:,
    expected_dimensions: nil,
    threshold: 0.03,
    expected_format: nil,
    enforce_size_ratio: true
  )
    directory = File.join(evidence_root, "images", id)
    FileUtils.mkdir_p(directory)
    raw_image_magick = File.join(directory, "image-magick#{File.extname(image_magick_path)}")
    raw_vips = File.join(directory, "vips#{File.extname(vips_path)}")
    image_magick_view = File.join(directory, "image-magick-view.png")
    vips_view = File.join(directory, "vips-view.png")
    diff = File.join(directory, "diff.png")
    metric_probe = File.join(directory, "metric-probe.png")
    FileUtils.cp(image_magick_path, raw_image_magick)
    FileUtils.cp(vips_path, raw_vips)
    run_command(
      "magick",
      raw_image_magick,
      "-alpha",
      "on",
      "-define",
      "png:color-type=6",
      image_magick_view,
    )
    run_command(
      "magick",
      raw_vips,
      "-alpha",
      "on",
      "-define",
      "png:color-type=6",
      vips_view,
    )
    _, metric_output, metric_status =
      Open3.capture3(
        "magick",
        "compare",
        "-metric",
        "MAE",
        image_magick_view,
        vips_view,
        metric_probe,
      )
    raise "Unable to compare #{id}: #{metric_output}" unless [0, 1].include?(metric_status.exitstatus)
    match = metric_output.match(/\(([\d.eE+-]+)\)/)
    raise "Unable to parse MAE for #{id}: #{metric_output}" unless match
    error = match[1].to_f
    FileUtils.rm_f(metric_probe)
    run_command(
      "magick",
      image_magick_view,
      vips_view,
      "-compose",
      "difference",
      "-composite",
      diff,
    )
    image_magick = image_info(raw_image_magick, "ImageMagick", image_magick_view)
    vips = image_info(raw_vips, "Stock libvips", vips_view)
    ratio = vips[:bytes].fdiv(image_magick[:bytes])
    dimensions_match = image_magick[:dimensions] == vips[:dimensions]
    dimensions_expected =
      expected_dimensions.nil? ||
        (
          image_magick[:dimensions] == expected_dimensions &&
            vips[:dimensions] == expected_dimensions
        )
    format_expected =
      expected_format.nil? ||
        (image_magick[:format] == expected_format && vips[:format] == expected_format)
    passed =
      dimensions_match && dimensions_expected && format_expected && error <= threshold &&
        (!enforce_size_ratio || ratio.between?(0.5, 2.0))
    @visual_cases << {
      id:,
      label:,
      entrypoint:,
      threshold:,
      before: image_magick,
      after: vips,
      diff_path: relative_path(diff),
      normalized_mean_rgba_error: error,
      size_ratio: ratio,
      passed:,
    }
    add_contract(
      id: "visual-#{id}",
      group: "Visual parity",
      description: "#{label}: dimensions, format, normalized RGBA MAE, and encoded-size ratio",
      expected: {
        dimensions: expected_dimensions || "identical",
        format: expected_format || "identical source format",
        normalized_mean_rgba_error_max: threshold,
        vips_to_image_magick_size_ratio:
          enforce_size_ratio ? [0.5, 2.0] : "informational due to metadata optimizer behavior",
      },
      actual: {
        image_magick_dimensions: image_magick[:dimensions],
        vips_dimensions: vips[:dimensions],
        image_magick_format: image_magick[:format],
        vips_format: vips[:format],
        normalized_mean_rgba_error: error,
        vips_to_image_magick_size_ratio: ratio,
      },
      passed:,
    )
  end

  def direct_pair(id:, label:, operation:, input:, arguments:, expected_dimensions: nil)
    Dir.mktmpdir("evidence-direct") do |directory|
      image_magick = File.join(directory, "image-magick.png")
      vips = File.join(directory, "vips.png")
      SiteSetting.use_vips_for_image_processing = false
      raise "#{operation} failed for ImageMagick" unless OptimizedImage.public_send(
        operation,
        input,
        image_magick,
        *arguments,
        raise_on_error: true,
      )
      SiteSetting.use_vips_for_image_processing = true
      raise "#{operation} failed for vips" unless OptimizedImage.public_send(
        operation,
        input,
        vips,
        *arguments,
        raise_on_error: true,
      )
      add_visual_case(
        id:,
        label:,
        entrypoint: "OptimizedImage.#{operation}",
        image_magick_path: image_magick,
        vips_path: vips,
        expected_dimensions:,
        expected_format: "png",
      )
    end
  end

  def upload_creator_output(
    use_vips:,
    source:,
    filename:,
    output:,
    options: {},
    settings: {}
  )
    SiteSetting.use_vips_for_image_processing = use_vips
    settings
      .sort_by { |name, _| name == :composer_media_optimization_image_enabled ? 0 : 1 }
      .each { |name, value| SiteSetting.public_send("#{name}=", value) }
    tempfile = fresh_input(source, File.extname(filename))
    upload =
      UploadCreator.new(tempfile, filename, { force_optimize: true }.merge(options)).create_for(
        evidence_user.id,
      )
    raise upload.errors.full_messages.join(", ") unless upload.persisted?
    path = Discourse.store.path_for(upload)
    FileUtils.cp(path, output)
    {
      upload_dimensions: [upload.width, upload.height],
      digest_matches: Upload.generate_digest(path) == upload.sha1,
      metadata: metadata_presence(path),
      orientation: orientation(path),
      extension: upload.extension,
      original_filename: upload.original_filename,
      animated: upload.animated,
      frames: frame_count(path),
    }
  ensure
    upload&.destroy
    tempfile&.close!
  end

  def upload_creator_pair(
    id:,
    label:,
    source:,
    filename:,
    expected_dimensions:,
    expected_format:,
    threshold: 0.03,
    options: {},
    settings: {}
  )
    Dir.mktmpdir("evidence-upload-creator") do |directory|
      image_magick = File.join(directory, "image-magick.#{expected_format}")
      vips = File.join(directory, "vips.#{expected_format}")
      image_magick_result =
        upload_creator_output(
          use_vips: false,
          source:,
          filename:,
          output: image_magick,
          options:,
          settings:,
        )
      vips_result =
        upload_creator_output(
          use_vips: true,
          source:,
          filename:,
          output: vips,
          options:,
          settings:,
        )
      add_visual_case(
        id:,
        label:,
        entrypoint: "UploadCreator#create_for",
        image_magick_path: image_magick,
        vips_path: vips,
        expected_dimensions:,
        expected_format: expected_format == "jpg" ? "jpeg" : expected_format,
        threshold:,
      )
      result_passed =
        image_magick_result[:upload_dimensions] == expected_dimensions &&
          vips_result[:upload_dimensions] == expected_dimensions &&
          image_magick_result[:digest_matches] && vips_result[:digest_matches]
      add_contract(
        id: "upload-state-#{id}",
        group: "Upload domain state",
        description: "#{label}: persisted dimensions and content digest",
        expected: { upload_dimensions: expected_dimensions, digest_matches: true },
        actual: {
          image_magick: image_magick_result.slice(:upload_dimensions, :digest_matches),
          vips: vips_result.slice(:upload_dimensions, :digest_matches),
        },
        passed: result_passed,
      )
      [image_magick_result, vips_result]
    end
  ensure
    settings.each_key do |name|
      SiteSetting.public_send("#{name}=", @base_settings.fetch(name.to_s))
    end
  end

  def thumbnail_output(use_vips:, size:, output:)
    SiteSetting.use_vips_for_image_processing = use_vips
    tempfile = fresh_input(fixture_path("large_and_unoptimized.png"))
    upload = UploadCreator.new(tempfile, "avatar-source.png").create_for(evidence_user.id)
    raise upload.errors.full_messages.join(", ") unless upload.persisted?
    upload.create_thumbnail!(size, size)
    optimized = upload.thumbnail(size, size)
    raise "No #{size}x#{size} optimized image" unless optimized
    FileUtils.cp(Discourse.store.path_for(optimized), output)
    {
      version: optimized.version,
      requested_dimensions: [optimized.width, optimized.height],
      file_dimensions: FastImage.size(output),
    }
  ensure
    optimized&.destroy
    upload&.destroy
    tempfile&.close!
  end

  def add_thumbnail_pair(size)
    Dir.mktmpdir("evidence-thumbnail") do |directory|
      image_magick = File.join(directory, "image-magick.png")
      vips = File.join(directory, "vips.png")
      image_magick_result = thumbnail_output(use_vips: false, size:, output: image_magick)
      vips_result = thumbnail_output(use_vips: true, size:, output: vips)
      add_visual_case(
        id: "uploaded-avatar-thumbnail-#{size}",
        label: "Uploaded-avatar thumbnail #{size}×#{size}",
        entrypoint: "Upload#create_thumbnail!",
        image_magick_path: image_magick,
        vips_path: vips,
        expected_dimensions: [size, size],
        expected_format: "png",
      )
      state_passed =
        image_magick_result == {
          version: OptimizedImage::VERSION,
          requested_dimensions: [size, size],
          file_dimensions: [size, size],
        } &&
          vips_result == {
            version: OptimizedImage::VIPS_VERSION,
            requested_dimensions: [size, size],
            file_dimensions: [size, size],
          }
      add_contract(
        id: "thumbnail-state-#{size}",
        group: "Uploaded-avatar thumbnails",
        description: "#{size}×#{size} thumbnail uses the processor-specific cache version",
        expected: {
          image_magick_version: OptimizedImage::VERSION,
          vips_version: OptimizedImage::VIPS_VERSION,
          dimensions: [size, size],
        },
        actual: { image_magick: image_magick_result, vips: vips_result },
        passed: state_passed,
      )
    end
  end

  def shrink_output(use_vips:, output:)
    SiteSetting.use_vips_for_image_processing = use_vips
    tempfile = fresh_input(fixture_path("large_and_unoptimized.png"))
    upload =
      Fabricate(
        :upload,
        width: 2032,
        height: 1312,
        filesize: File.size(tempfile.path),
        sha1: Upload.generate_digest(tempfile.path),
        original_filename: "shrink-source.png",
        extension: "png",
      )
    upload.update!(url: Discourse.store.store_upload(tempfile, upload))
    post =
      Fabricate(
        :post,
        raw: "<img src='#{upload.url}'>",
        user: evidence_user,
      )
    post.link_post_uploads
    result =
      ShrinkUploadedImage.new(
        upload:,
        path: Discourse.store.path_for(upload),
        max_pixels: 10_000,
      ).perform
    upload.reload
    path = Discourse.store.path_for(upload)
    FileUtils.cp(path, output)
    {
      result:,
      upload_dimensions: [upload.width, upload.height],
      file_dimensions: FastImage.size(path),
      format: FastImage.type(path).to_s,
      digest_matches: Upload.generate_digest(path) == upload.sha1,
    }
  ensure
    post&.destroy
    upload&.destroy
    tempfile&.close!
  end

  def write_oriented_jpeg(source:, target:, orientation:)
    Vips.run(
      "vips",
      "copy",
      source,
      "#{target}[Q=82,strip=true]",
      read: [source],
      write: [File.dirname(target)],
    )
    jpeg = File.binread(target)
    tiff =
      "II".b + [42].pack("v") + [8].pack("V") + [1].pack("v") + [0x0112, 3].pack("v2") +
        [1].pack("V") + [orientation, 0].pack("v2") + [0].pack("V")
    payload = "Exif\0\0".b + tiff
    segment = "\xFF\xE1".b + [payload.bytesize + 2].pack("n") + payload
    File.binwrite(target, jpeg.byteslice(0, 2) + segment + jpeg.byteslice(2..))
  end

  def add_metadata_pair(strip_metadata)
    Dir.mktmpdir("evidence-metadata") do |directory|
      image_magick = File.join(directory, "image-magick.png")
      vips = File.join(directory, "vips.png")
      SiteSetting.composer_media_optimization_image_enabled = false
      SiteSetting.strip_image_metadata = strip_metadata
      SiteSetting.use_vips_for_image_processing = false
      OptimizedImage.resize(
        fixture_path("large_and_unoptimized.png"),
        image_magick,
        320,
        200,
        raise_on_error: true,
      )
      SiteSetting.use_vips_for_image_processing = true
      OptimizedImage.resize(
        fixture_path("large_and_unoptimized.png"),
        vips,
        320,
        200,
        raise_on_error: true,
      )
      id = strip_metadata ? "metadata-stripped" : "metadata-preserved"
      add_visual_case(
        id:,
        label: strip_metadata ? "Metadata stripped" : "Metadata preserved",
        entrypoint: "OptimizedImage.resize",
        image_magick_path: image_magick,
        vips_path: vips,
        expected_dimensions: [320, 200],
        expected_format: "png",
        enforce_size_ratio: strip_metadata,
      )
      actual = {
        image_magick: metadata_presence(image_magick),
        vips: metadata_presence(vips),
      }
      stripped_fields = {
        "exif-data" => false,
        "xmp-data" => false,
        "iptc-data" => false,
        "icc-profile-data" => false,
      }
      preserved_vips_fields = {
        "exif-data" => true,
        "xmp-data" => true,
        "iptc-data" => false,
        "icc-profile-data" => true,
      }
      expected =
        if strip_metadata
          { image_magick: stripped_fields, vips: stripped_fields }
        else
          { image_magick: stripped_fields, vips: preserved_vips_fields }
        end
      passed =
        actual == {
          image_magick: expected[:image_magick],
          vips: expected[:vips],
        }
      add_contract(
        id: "metadata-fields-#{strip_metadata ? "strip" : "preserve"}",
        group: strip_metadata ? "Metadata" : "Expected divergence",
        description:
          if strip_metadata
            "Both processors strip exposed metadata"
          else
            "Stock libvips preserves exposed EXIF, XMP, and ICC while legacy ImageMagick plus pngquant loses them"
          end,
        expected:,
        actual:,
        passed:,
      )
      if !strip_metadata
        add_finding(
          id: "metadata-preservation-divergence",
          group: "Expected divergence",
          label: "Metadata preservation improves with stock libvips",
          details: {
            behavior: actual,
            encoded_size_ratio: @visual_cases.last[:size_ratio],
            explanation:
              "The stock-libvips path disables pngquant when metadata must be preserved; the legacy ImageMagick path does not.",
          },
          passed:,
        )
      end
    end
  ensure
    SiteSetting.strip_image_metadata = @base_settings.fetch("strip_image_metadata")
    SiteSetting.composer_media_optimization_image_enabled =
      @base_settings.fetch("composer_media_optimization_image_enabled")
  end

  def add_animation_findings
    generated_avif = File.join(evidence_root, "sources", "animated.avif")
    Vips.run(
      "vips",
      "copy",
      "#{fixture_path("animated.webp")}[n=-1]",
      generated_avif,
      read: [fixture_path("animated.webp")],
      write: [File.dirname(generated_avif)],
    )
    cases = {
      "animated.gif" => [fixture_path("animated.gif"), true, 20],
      "animated.webp" => [fixture_path("animated.webp"), true, 67],
      "animated.avif" => [generated_avif, true, 67],
      "static.png" => [fixture_path("logo.png"), false, 1],
    }
    FastImage.stubs(:animated?).returns(nil)
    results =
      cases.to_h do |label, (source, _, _)|
        processor_results =
          [false, true].to_h do |use_vips|
            SiteSetting.use_vips_for_image_processing = use_vips
            tempfile = fresh_input(source)
            upload =
              UploadCreator.new(tempfile, label, force_optimize: true).create_for(evidence_user.id)
            raise upload.errors.full_messages.join(", ") unless upload.persisted?
            path = Discourse.store.path_for(upload)
            result = { animated: upload.animated, frames: frame_count(path) }
            upload.destroy
            tempfile.close!
            [processor_name(use_vips), result]
          end
        [label, processor_results]
      end
    expected =
      cases.transform_values do |(_, animated, frames)|
        {
          "ImageMagick" => {
            animated:,
            frames:,
          },
          "Stock libvips" => {
            animated:,
            frames:,
          },
        }
      end
    passed = results == expected
    add_contract(
      id: "animation-frame-classification",
      group: "Animation",
      description: "Both processors classify GIF, WebP, AVIF, and static PNG when FastImage is inconclusive",
      expected:,
      actual: results,
      passed:,
    )
    add_finding(
      id: "animation",
      group: "Animation",
      label: "Animation and frame classification",
      details: results,
      passed:,
    )
  ensure
    FastImage.unstub(:animated?) if FastImage.respond_to?(:unstub)
  end

  def add_svg_findings
    expected_dimensions = {
      "tiny.svg" => [115, 86],
      "massive.svg" => [11_520, 11_615],
      "zero_sized.svg" => [120, 90],
    }
    results =
      expected_dimensions.to_h do |filename, _|
        processors =
          [false, true].to_h do |use_vips|
            SiteSetting.use_vips_for_image_processing = use_vips
            tempfile = fresh_input(fixture_path(filename))
            upload =
              UploadCreator.new(
                tempfile,
                filename,
                force_optimize: true,
              ).create_for(evidence_user.id)
            raise upload.errors.full_messages.join(", ") unless upload.persisted?
            stored_path = Discourse.store.path_for(upload)
            upload.update_columns(
              width: nil,
              height: nil,
              thumbnail_width: nil,
              thumbnail_height: nil,
            )
            upload.fix_dimensions!
            result = {
              dimensions: [upload.width, upload.height],
              thumbnail_dimensions: [upload.thumbnail_width, upload.thumbnail_height],
              optimized_byte_copy:
                begin
                  optimized = OptimizedImage.create_for(upload, 96, 64, raise_on_error: true)
                  Digest::SHA256.file(Discourse.store.path_for(optimized)).hexdigest ==
                    Digest::SHA256.file(stored_path).hexdigest
                ensure
                  optimized&.destroy
                end,
            }
            upload.destroy
            tempfile.close!
            [processor_name(use_vips), result]
          end
        [filename, processors]
      end
    expected_thumbnail_dimensions = {
      "tiny.svg" => [115, 86],
      "massive.svg" => [495, 500],
      "zero_sized.svg" => [120, 90],
    }
    expected =
      expected_dimensions.to_h do |filename, dimensions|
        processor_result = {
          dimensions:,
          thumbnail_dimensions: expected_thumbnail_dimensions.fetch(filename),
          optimized_byte_copy: true,
        }
        [
          filename,
          {
            "ImageMagick" => processor_result,
            "Stock libvips" => processor_result,
          },
        ]
      end
    passed = results == expected
    add_contract(
      id: "svg-dimensions-and-byte-copy",
      group: "SVG",
      description: "Both processors store, repair, and byte-copy SVGs with pixel, huge, and zero/viewBox dimensions",
      expected:,
      actual: results,
      passed:,
    )
    add_finding(
      id: "svg",
      group: "SVG",
      label: "SVG dimensions and optimized byte-copy",
      details: results,
      passed:,
    )
  end

  def add_quality_findings
    directory = File.join(evidence_root, "sources")
    source = fixture_path("logo.jpg")
    low = File.join(directory, "quality-50.jpg")
    high = File.join(directory, "quality-90.jpg")
    malformed = File.join(directory, "malformed.jpg")
    Vips.run("vips", "copy", source, "#{low}[Q=50]", read: [source], write: [directory])
    Vips.run("vips", "copy", source, "#{high}[Q=90]", read: [source], write: [directory])
    File.binwrite(malformed, "not a jpeg")
    results =
      [false, true].to_h do |use_vips|
        SiteSetting.use_vips_for_image_processing = use_vips
        [
          processor_name(use_vips),
          {
            quality_50_target_70: Upload.new.target_image_quality(low, 70),
            quality_90_target_70: Upload.new.target_image_quality(high, 70),
            malformed_target_70: Upload.new.target_image_quality(malformed, 70),
          },
        ]
      end
    expected = {
        "ImageMagick" => {
          quality_50_target_70: 70,
          quality_90_target_70: 70,
          malformed_target_70: 70,
        },
        "Stock libvips" => {
          quality_50_target_70: nil,
          quality_90_target_70: 70,
          malformed_target_70: 70,
        },
      }
    passed = results == expected
    add_contract(
      id: "jpeg-quality-selection",
      group: "Expected divergence",
      description: "jhead recognizes the Q50 source and avoids up-encoding it while ImageMagick reports an unavailable estimate",
      expected:,
      actual: results,
      passed:,
    )
    add_finding(
      id: "jpeg-quality-divergence",
      group: "Expected divergence",
      label: "Source-quality estimation avoids a needless Q50 to Q70 re-encode",
      details: {
        behavior: results,
        explanation:
          "The immutable source is Vips-encoded. ImageMagick percent-Q reports it as unavailable while jhead estimates Q50; Q90 and malformed inputs retain the intended target-70 behavior.",
      },
      passed:,
    )
    add_finding(
      id: "jpeg-quality",
      group: "JPEG quality",
      label: "JPEG quality selection",
      details: results,
      passed:,
    )
  end

  def add_format_findings
    extensions = %w[jpg jpeg png gif svg ico webp avif heic heif jxl tiff bmp]
    allowlist = extensions.to_h { |extension| [extension, FileHelper.is_supported_image?("x.#{extension}")] }
    expected_allowlist =
      extensions.to_h do |extension|
        [extension, %w[jpg jpeg png gif svg ico webp avif heic heif jxl].include?(extension)]
      end
    jxl_results =
      [false, true].to_h do |use_vips|
        SiteSetting.use_vips_for_image_processing = use_vips
        upload = Fabricate(:upload, sha1: "a" * 40, extension: "jxl", original_filename: "x.jxl")
        optimized = OptimizedImage.create_for(upload, 96, 64)
        upload.destroy
        [processor_name(use_vips), optimized.nil?]
      end
    passed =
      allowlist == expected_allowlist &&
        jxl_results == { "ImageMagick" => true, "Stock libvips" => true }
    details = {
      upload_allowlist: allowlist,
      optimized_decoder_allowlist: OptimizedImage::IM_DECODERS.source,
      jxl_returns_no_optimized_image: jxl_results,
      tiff_and_bmp_outside_upload_allowlist: !allowlist["tiff"] && !allowlist["bmp"],
    }
    add_contract(
      id: "format-eligibility",
      group: "Formats",
      description: "Upload allowlist and optimized-image eligibility remain processor-independent",
      expected: {
        upload_allowlist: expected_allowlist,
        jxl_returns_no_optimized_image: {
          "ImageMagick" => true,
          "Stock libvips" => true,
        },
      },
      actual: details,
      passed:,
    )
    add_finding(
      id: "formats",
      group: "Formats",
      label: "Format eligibility",
      details:,
      passed:,
    )
  end

  def add_ico_finding
    original = @base_settings.fetch("authorized_extensions")
    SiteSetting.authorized_extensions = "#{original}|ico"
    image_magick =
      begin
        SiteSetting.use_vips_for_image_processing = false
        tempfile = fresh_input(fixture_path("smallest.ico"))
        upload = UploadCreator.new(tempfile, "smallest.ico").create_for(evidence_user.id)
        result = {
          persisted: upload.persisted?,
          extension: upload.extension,
          format: upload.persisted? ? FastImage.type(Discourse.store.path_for(upload)).to_s : nil,
        }
        upload.destroy if upload.persisted?
        tempfile.close!
        result
      end
    vips_error =
      begin
        SiteSetting.use_vips_for_image_processing = true
        tempfile = fresh_input(fixture_path("smallest.ico"))
        UploadCreator.new(tempfile, "smallest.ico").create_for(evidence_user.id)
        nil
      rescue => error
        error.class.name
      ensure
        tempfile&.close!
      end
    expected = {
      image_magick: {
        persisted: true,
        extension: "png",
        format: "png",
      },
      vips_error: "Discourse::Utils::CommandError",
    }
    actual = { image_magick:, vips_error: }
    passed = actual == expected
    add_contract(
      id: "ico-deliberate-enabled-failure",
      group: "Documented exception",
      description: "ICO succeeds through ImageMagick and deliberately raises through enabled stock libvips with no fallback",
      expected:,
      actual:,
      passed:,
    )
    add_finding(
      id: "ico",
      group: "Documented exception",
      label: "ICO enabled-path failure",
      details: actual,
      passed:,
    )
  ensure
    SiteSetting.authorized_extensions = original
  end

  it "writes complete both-arm production-entrypoint evidence" do
    FileUtils.rm_rf(evidence_root)
    FileUtils.mkdir_p(File.join(evidence_root, "images"))
    FileUtils.mkdir_p(File.join(evidence_root, "sources"))
    @contracts = []
    @findings = []
    @visual_cases = []
    @base_settings = {
      "avatar_sizes" => "24|48|72|96|144|288",
      "image_quality" => 90,
      "png_to_jpg_quality" => 0,
      "recompress_original_jpg_quality" => 0,
      "image_preview_jpg_quality" => 0,
      "strip_image_metadata" => true,
      "composer_media_optimization_image_enabled" => true,
      "authorized_extensions" => "jpg|jpeg|png|gif|heic|heif|webp|avif|svg|jxl",
    }
    @base_settings.each { |name, value| SiteSetting.public_send("#{name}=", value) }

    direct_pair(
      id: "resize-321x123",
      label: "Representative non-square resize 321×123",
      operation: :resize,
      input: fixture_path("large_and_unoptimized.png"),
      arguments: [321, 123],
      expected_dimensions: [321, 123],
    )
    direct_pair(
      id: "north-crop-landscape-321x123",
      label: "North crop landscape 321×123",
      operation: :crop,
      input: fixture_path("large_and_unoptimized.png"),
      arguments: [321, 123],
      expected_dimensions: [321, 123],
    )
    direct_pair(
      id: "north-crop-portrait-173x419",
      label: "North crop portrait 173×419",
      operation: :crop,
      input: fixture_path("large_and_unoptimized.png"),
      arguments: [173, 419],
      expected_dimensions: [173, 419],
    )
    direct_pair(
      id: "north-crop-alpha-96x160",
      label: "North crop with alpha 96×160",
      operation: :crop,
      input: fixture_path("logo.png"),
      arguments: [96, 160],
      expected_dimensions: [96, 160],
    )
    [
      ["downsize-percentage", "Downsize 50%", "50%", [1016, 656]],
      ["downsize-area", "Downsize to 500,000 pixels", "500000@", nil],
      ["downsize-shrink-only", "Downsize shrink-only 333×222", "333x222>", [333, 215]],
    ].each do |id, label, geometry, dimensions|
      direct_pair(
        id:,
        label:,
        operation: :downsize,
        input: fixture_path("large_and_unoptimized.png"),
        arguments: [geometry],
        expected_dimensions: dimensions,
      )
    end
    direct_pair(
      id: "downsize-no-upscale-alpha",
      label: "Downsize no-upscale with alpha",
      operation: :downsize,
      input: fixture_path("logo.png"),
      arguments: ["500x500>"],
      expected_dimensions: [244, 66],
    )

    SiteSetting.avatar_sizes.split("|").map(&:to_i).each { |size| add_thumbnail_pair(size) }

    upload_creator_pair(
      id: "avatar-original-normalization",
      label: "Avatar original normalization",
      source: fixture_path("large_and_unoptimized.png"),
      filename: "avatar.png",
      expected_dimensions: [288, 288],
      expected_format: "png",
      options: {
        type: "avatar",
      },
    )
    upload_creator_pair(
      id: "png-to-jpeg",
      label: "Pasted PNG to JPEG conversion",
      source: fixture_path("should_be_jpeg.png"),
      filename: "should_be_jpeg.png",
      expected_dimensions: [303, 231],
      expected_format: "jpg",
      options: {
        pasted: true,
      },
      settings: {
        png_to_jpg_quality: 80,
      },
    )
    upload_creator_pair(
      id: "heic-to-jpeg",
      label: "HEIC to JPEG conversion",
      source: fixture_path("should_be_jpeg.heic"),
      filename: "should_be_jpeg.heic",
      expected_dimensions: [846, 1129],
      expected_format: "jpg",
    )
    generated_heif = File.join(evidence_root, "sources", "generated.heif")
    Vips.run(
      "vips",
      "copy",
      fixture_path("large_and_unoptimized.png"),
      "#{generated_heif}[Q=82]",
      read: [fixture_path("large_and_unoptimized.png")],
      write: [File.dirname(generated_heif)],
    )
    upload_creator_pair(
      id: "heif-to-jpeg",
      label: "Generated HEIF to JPEG conversion",
      source: generated_heif,
      filename: "generated.heif",
      expected_dimensions: [2032, 1312],
      expected_format: "jpg",
    )

    (2..8).each do |source_orientation|
      source = File.join(evidence_root, "sources", "orientation-#{source_orientation}.jpg")
      write_oriented_jpeg(
        source: fixture_path("large_and_unoptimized.png"),
        target: source,
        orientation: source_orientation,
      )
      expected_dimensions = source_orientation <= 4 ? [2032, 1312] : [1312, 2032]
      image_magick_result, vips_result =
        upload_creator_pair(
          id: "orientation-#{source_orientation}",
          label: "EXIF orientation #{source_orientation}",
          source:,
          filename: "orientation-#{source_orientation}.jpg",
          expected_dimensions:,
          expected_format: "jpg",
          threshold: 0.10,
          settings: {
            strip_image_metadata: false,
            composer_media_optimization_image_enabled: false,
          },
        )
      orientation_passed =
        image_magick_result[:orientation] == 1 && vips_result[:orientation] == 1
      add_contract(
        id: "orientation-reset-#{source_orientation}",
        group: "EXIF orientation",
        description: "Orientation #{source_orientation} is rewritten to upright pixels and tag 1",
        expected: {
          dimensions: expected_dimensions,
          orientation: 1,
          digest_matches: true,
        },
        actual: {
          image_magick: image_magick_result.slice(
            :upload_dimensions,
            :orientation,
            :digest_matches,
          ),
          vips: vips_result.slice(:upload_dimensions, :orientation, :digest_matches),
        },
        passed: orientation_passed,
      )
    end

    add_metadata_pair(false)
    add_metadata_pair(true)

    Dir.mktmpdir("evidence-shrink") do |directory|
      image_magick = File.join(directory, "image-magick.png")
      vips = File.join(directory, "vips.png")
      image_magick_result = shrink_output(use_vips: false, output: image_magick)
      vips_result = shrink_output(use_vips: true, output: vips)
      add_visual_case(
        id: "shrink-uploaded-image",
        label: "Stored original normalization to 10,000 pixels",
        entrypoint: "ShrinkUploadedImage#perform",
        image_magick_path: image_magick,
        vips_path: vips,
        expected_dimensions: [124, 80],
        expected_format: "png",
      )
      expected = {
        result: true,
        upload_dimensions: [124, 80],
        file_dimensions: [124, 80],
        format: "png",
        digest_matches: true,
      }
      add_contract(
        id: "shrink-uploaded-image-state",
        group: "Original normalization",
        description: "Both processors update stored bytes, dimensions, and digest through ShrinkUploadedImage",
        expected:,
        actual: {
          image_magick: image_magick_result,
          vips: vips_result,
        },
        passed: image_magick_result == expected && vips_result == expected,
      )
    end

    add_animation_findings
    add_svg_findings
    add_quality_findings
    add_format_findings
    add_ico_finding

    failures = @contracts.reject { |contract| contract[:passed] }
    manifest = {
      title: "Discourse stock libvips image-processing parity",
      generated_at: Time.now.utc.iso8601,
      overall_pass: failures.empty?,
      summary: {
        contracts: @contracts.length,
        passed: @contracts.length - failures.length,
        failed: failures.length,
        visual_cases: @visual_cases.length,
      },
      provenance: JSON.parse(ENV.fetch("EVIDENCE_PROVENANCE")),
      settings: @base_settings,
      thresholds: {
        normal_normalized_mean_rgba_error: 0.03,
        independently_reencoded_orientation_error: 0.10,
        vips_to_image_magick_size_ratio: [0.5, 2.0],
      },
      contracts: @contracts,
      visual_cases: @visual_cases,
      findings: @findings,
      notes: [
        "This is end-to-end production-entrypoint parity, not a raw-library microbenchmark.",
        "No VIPS_CONCURRENCY, MAGICK_THREAD_LIMIT, or processor-specific concurrency override was set.",
        "Uploaded-avatar thumbnail rows are not LetterAvatar generation; LetterAvatar is unconditional stock libvips at this commit.",
        "With metadata preservation enabled, the stock-libvips path deliberately disables pngquant while ImageMagick does not; encoded-size differences include that production behavior.",
        "All transformations use fresh Upload, UploadCreator, and tempfile instances per processor arm.",
        "PNG32 report views, RGBA MAE, and difference images are generated after domain processing with the same ImageMagick decoder for both outputs.",
        "JPEG quality values reported by identify and jhead are estimates used by production selection logic.",
        "The enabled stock-libvips ICO failure is a deliberate documented exception and has no ImageMagick fallback.",
      ],
    }
    File.write(File.join(evidence_root, "manifest.json"), JSON.pretty_generate(manifest))
    expect(failures).to eq([])
  end
end
