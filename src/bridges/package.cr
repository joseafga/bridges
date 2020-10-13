require "yaml"

module Bridges
  class Package
    def initialize
    end

    def create(from : String, dest = ".")
      # raise "Bridges: metadata is empty" if @name.empty? || @version.empty?
      # TODO: use File.tempfile for big files?
      # path = File.join(dest, "test_0.2.0.pkg")
      tarball = IO::Memory.new

      # File.open(path, "w+") do |tarball| # read and write
      write_metadata(tarball, from).archive(tarball, from)

      tarball.rewind
      compress(tarball, dest)
      # end
    end

    def write_metadata(io : IO, from : String) : Package
      # TODO: Use struct
      path = File.join(from, "package.yml")

      # metadata = YAML.parse(File.read(path))
      metadata = File.read(path)

      io.write_bytes(metadata.bytesize) # 4 bytes metadata size information
      io << metadata

      self
    end

    def archive(io : IO, from : String)
      Crystar::Writer.open(io) do |tw|
        path = File.join(from, "test_0.2.0")

        Dir.cd(path) do
          Dir["**/*"].each do |filename|
            header = file_header(filename)

            # Write TAR data
            tw.write_header header
            File.open(filename) { |f| IO.copy(f, tw) } if header.size > 0
          end
        end
      end
    end

    def compress(io : IO, dest : String)
      filename = File.join(dest, "test_0.2.0.pkg.lz4")
      lz4_options = Compress::LZ4::CompressOptions.new(
        checksum: true,
        compression_level: Compress::LZ4::CompressOptions::CompressionLevel::MIN
      )

      Compress::LZ4::Writer.open(filename, lz4_options) { |cio| IO.copy(io, cio) }
    end

    # Decompress single frame
    def decompress(from : String)
      filename = File.join(from, "test_0.2.0.pkg.lz4")
      metadata = ""

      File.open(filename) do |file|
        Compress::LZ4::Reader.open(file) do |cio|
          metasize = cio.read_bytes(Int32)
          raise "Bridges: can't read metadata" if metasize.nil?

          metadata = cio.read_string(metasize)

          # just for benchmark
          File.open(File.join(from, "package.yml"), "w") { |f| f.puts metadata }
          # metadata = YAML.parse(metadata) unless metadata.nil?
          # raise "Bridges: can't read metadata" if metadata.nil?

          # skipping the rest
          
          # Crystar::Reader.open(cio) do |io|
          #   io.each_entry do |entry|
          #     p "Contents of #{entry.name}"
          #     IO.copy entry.io, STDOUT
          #   end
          # end
        end
      end

      metadata
    end

    # Based on Crystar.file_info_header
    def file_header(path : String)
      info = File.info(path, follow_symlinks: false)
      header = Header.new(
        format: Crystar::Format::GNU,
        name: path,
        mod_time: info.modification_time,
        mode: info.permissions.value.to_i64,
        uid: info.owner_id.to_i32,
        gid: info.group_id.to_i32,
      )

      case info.type
      when .file?
        header.flag = Crystar::REG.ord.to_u8
        header.size = info.size
      when .directory?
        header.flag = Crystar::DIR.ord.to_u8
        header.name += '/'
      when .symlink?
        header.flag = Crystar::SYMLINK.ord.to_u8
        header.link_name = File.readlink(path)
      when .character_device?
        header.flag = Crystar::CHAR.ord.to_u8
      when .block_device?
        header.flag = Crystar::BLOCK.ord.to_u8
      when .pipe?
        header.flag = Crystar::FIFO.ord.to_u8
      when .socket?
        raise "Crystar Lib: sockets not supported"
      else
        raise "Crystar Lib: unknown file type #{info}"
      end

      header
    end
  end
end
