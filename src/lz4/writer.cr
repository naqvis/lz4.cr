require "./lib"

# A write-only `IO` object to compress data in the LZ4 format.
#
# Instances of this class wrap another `IO` object. When you write to this
# instance, it compresses the data and writes it to the underlying `IO`.
#
# NOTE: unless created with a block, `close` must be invoked after all
# data has been written to a `LZ4::Writer` instance.
#
# ### Example: compress a file
#
# ```
# require "lz4"
#
# File.write("file.txt", "abcd")
#
# File.open("./file.txt", "r") do |input_file|
#   File.open("./file.lz4", "w") do |output_file|
#     Compress::LZ4::Writer.open(output_file) do |lz4|
#       IO.copy(input_file, lz4)
#     end
#   end
# end
# ```
class Compress::LZ4::Writer < IO
  property? sync_close : Bool
  getter? closed = false
  @context : LibLZ4::Cctx
  @pref : LibLZ4::PreferencesT
  @header_written = false

  def initialize(@output : IO, options = CompressOptions.new, @sync_close = false)
    ret = LibLZ4.create_compression_context(out @context, LibLZ4::VERSION)
    raise_if_error(ret, "Failed to create compression context")
    @pref = options.to_preferences
    @block_size = case options.block_size
                  in BlockSize::Default  then 64 * 1024
                  in BlockSize::Max64Kb  then 64 * 1024
                  in BlockSize::Max256Kb then 256 * 1024
                  in BlockSize::Max1Mb   then 1024 * 1024
                  in BlockSize::Max4Mb   then 4 * 1024 * 1024
                  end
    buffer_size = LibLZ4.compress_frame_bound(@block_size, pointerof(@pref))
    @buffer = Bytes.new(buffer_size)
  end

  # Creates a new writer to the given *filename*.
  def self.new(filename : String, options : CompressOptions = CompressOptions.default)
    new(::File.new(filename, "w"), options: options, sync_close: true)
  end

  # Creates a new writer to the given *io*, yields it to the given block,
  # and closes it at the end.
  def self.open(io : IO, options : CompressOptions = CompressOptions.default, sync_close = false)
    writer = new(io, options: options, sync_close: sync_close)
    yield writer ensure writer.close
  end

  # Creates a new writer to the given *filename*, yields it to the given block,
  # and closes it at the end.
  def self.open(filename : String, options : CompressOptions = CompressOptions.default)
    writer = new(filename, options: options)
    yield writer ensure writer.close
  end

  # Creates a new writer for the given *io*, yields it to the given block,
  # and closes it at its end.
  def self.open(io : IO, options : CompressOptions = CompressOptions.default, sync_close : Bool = false)
    writer = new(io, options: options, sync_close: sync_close)
    yield writer ensure writer.close
  end

  def read(slice : Bytes)
    raise IO::Error.new "Can't read from LZ4::Writer"
  end

  private def write_header
    return if @header_written
    ret = LibLZ4.compress_begin(@context, @buffer, @buffer.size, nil)
    raise_if_error(ret, "Failed to begin compression")
    @output.write(@buffer[0, ret])
    @header_written = true
  end

  def write(slice : Bytes) : Nil
    check_open
    write_header
    opts = LibLZ4::CompressOptionsT.new(stable_src: 1)
    until slice.empty?
      read_size = Math.min(slice.size, @block_size)
      ret = LibLZ4.compress_update(@context, @buffer, @buffer.size, slice, read_size, pointerof(opts))
      raise_if_error(ret, "Failed to compress")
      @output.write(@buffer[0, ret])
      slice = slice + read_size
    end
  end

  def flush : Nil
    check_open
    ret = LibLZ4.flush(@context, @buffer, @buffer.size, nil)
    raise_if_error(ret, "Failed to flush")
    @output.write(@buffer[0, ret])
    @output.flush
  end

  # Ends a LZ4 frame, the stream can still be written to, unless @sync_close
  def close
    check_open
    ret = LibLZ4.compress_end(@context, @buffer, @buffer.size, nil)
    raise_if_error(ret, "Failed to end compression")
    @output.write(@buffer[0, ret])
    @header_written = false
  ensure
    if @sync_close
      @closed = true # the stream can still be written to
      @output.close
    end
  end

  def finalize
    LibLZ4.free_compression_context(@context)
  end

  def closed? : Bool
    @closed
  end

  private def raise_if_error(ret : Int, msg : String)
    unless LibLZ4.is_error(ret).zero?
      raise LZ4Error.new("#{msg}: #{String.new(LibLZ4.get_error_name(ret))}")
    end
  end

  # :nodoc:
  def inspect(io : IO) : Nil
    to_s(io)
  end
end

alias Compress::LZ4::BlockSize = Compress::LZ4::LibLZ4::BlockSizeIdT

struct Compress::LZ4::CompressOptions
  enum CompressionLevel
    FAST    =  0
    MIN     =  3
    DEFAULT =  9
    OPT_MIN = 10
    MAX     = 12
  end
  property block_size : BlockSize
  property block_mode_linked : Bool
  property checksum : Bool
  property compression_level : CompressionLevel
  property auto_flush : Bool
  property favor_decompression_speed : Bool

  def initialize(@block_size = BlockSize::Default, @block_mode_linked = true, @checksum = false,
                 @compression_level = CompressionLevel::FAST, @auto_flush = false,
                 @favor_decompression_speed = false)
  end

  def self.default
    new
  end

  protected def to_preferences
    pref = LibLZ4::PreferencesT.new
    pref.frame_info.block_size_id = block_size
    pref.frame_info.block_mode = LibLZ4::BlockModeT.from_value(block_mode_linked ? 0 : 1)
    pref.frame_info.content_checksum_flag = LibLZ4::ContentChecksumT.from_value(checksum ? 1 : 0)
    pref.frame_info.frame_type = LibLZ4::FrameTypeT::Frame
    pref.frame_info.content_size = 0
    pref.frame_info.dict_id = 0
    pref.frame_info.block_checksum_flag = LibLZ4::BlockChecksumT::NoBlockChecksum

    pref.compression_level = compression_level.value
    pref.auto_flush = auto_flush ? 1 : 0
    pref.favor_dec_speed = favor_decompression_speed ? 1 : 0

    pref.reserved = StaticArray[0_u32, 0_u32, 0_u32]

    pref
  end
end
