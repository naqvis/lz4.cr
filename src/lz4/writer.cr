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
#     LZ4::Writer.open(output_file) do |lz4|
#       IO.copy(input_file, lz4)
#     end
#   end
# end
# ```
class LZ4::Writer < IO
  # If `#sync_close?` is `true`, closing this IO will close the underlying IO.
  property? sync_close : Bool
  @context : LibLZ4::Cctx
  CHUNK_SIZE = 64 * 1024
  @pref : LibLZ4::PreferencesT

  def initialize(@output : IO, options : CompressOptions = WriterOptions.default, @sync_close : Bool = false)
    ret = LibLZ4.create_compression_context(out @context, LibLZ4::VERSION)
    raise LZ4Error.new("Unable to create lz4 encoder instance: #{String.new(LibLZ4.get_error_name(ret))}") unless LibLZ4.is_error(ret) == 0

    @pref = options.to_preferences
    buf_size = LibLZ4.compress_frame_bound(CHUNK_SIZE, pointerof(@pref))
    @buffer = Bytes.new(buf_size)

    @header_written = false
    @closed = false
  end

  # Creates a new writer to the given *filename*.
  def self.new(filename : String, options : CompressOptions = CompressOptions.default)
    new(::File.new(filename, "w"), options: options, sync_close: true)
  end

  # Creates a new writer to the given *io*, yields it to the given block,
  # and closes it at the end.
  def self.open(io : IO, options : CompressOptions = CompressOptions.default, sync_close = false)
    writer = new(io, preset: preset, sync_close: sync_close)
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

  # Always raises `IO::Error` because this is a write-only `IO`.
  def read(slice : Bytes)
    raise IO::Error.new "Can't read from LZ4::Writer"
  end

  private def write_header
    return if @header_written
    @buffer.to_unsafe.clear(@buffer.size)
    header_size = LibLZ4.compress_begin(@context, @buffer.to_unsafe, @buffer.size, pointerof(@pref))
    raise LZ4Error.new("Failed to start compression: #{String.new(LibLZ4.get_error_name(header_size))}") unless LibLZ4.is_error(header_size) == 0
    @output.write(@buffer[...header_size]) if header_size > 0
    @header_written = true
  end

  # See `IO#write`.
  def write(slice : Bytes) : Nil
    check_open
    return if slice.empty?
    write_header

    while slice.size > 0
      write_size = slice.size
      write_size = @buffer.size if write_size > @buffer.size
      @buffer.to_unsafe.clear(@buffer.size)

      comp_size = LibLZ4.compress_update(@context, @buffer.to_unsafe, @buffer.size, slice.to_unsafe, write_size, nil)
      raise LZ4Error.new("Compression failed: #{String.new(LibLZ4.get_error_name(comp_size))}") unless LibLZ4.is_error(comp_size) == 0
      @output.write(@buffer[...comp_size]) if comp_size > 0
      # 0 means data was buffered, to avoid buffer too small problem at end,
      # let's flush the data manually
      flush if comp_size == 0
      slice = slice[write_size..]
    end
  end

  # See `IO#flush`.
  def flush
    return if @closed
    @buffer.to_unsafe.clear(@buffer.size)

    ret = LibLZ4.flush(@context, @buffer.to_unsafe, @buffer.size, nil)
    raise LZ4Error.new("Flush failed: #{String.new(LibLZ4.get_error_name(ret))}") unless LibLZ4.is_error(ret) == 0
    @output.write(@buffer[...ret]) if ret > 0
  end

  # Closes this writer. Must be invoked after all data has been written.
  def close
    return if @closed || @context.nil?

    @buffer.to_unsafe.clear(@buffer.size)
    comp_size = LibLZ4.compress_end(@context, @buffer.to_unsafe, @buffer.size, nil)
    raise LZ4Error.new("Failed to end compression: #{String.new(LibLZ4.get_error_name(comp_size))}") unless LibLZ4.is_error(comp_size) == 0
    @output.write(@buffer[...comp_size]) if comp_size > 0
    @header_written = false

    LibLZ4.free_compression_context(@context)
    @closed = true
    @output.close if @sync_close
  end

  # Returns `true` if this IO is closed.
  def closed?
    @closed
  end

  # :nodoc:
  def inspect(io : IO) : Nil
    to_s(io)
  end
end

struct LZ4::CompressOptions
  enum CompressionLevel
    FAST    =  0
    MIN     =  3
    DEFAULT =  9
    OPT_MIN = 10
    MAX     = 12
  end
  # block size
  property block_size : LibLZ4::BlockSizeIdT
  property block_mode_linked : Bool
  property checksum : Bool
  property compression_level : CompressionLevel
  property auto_flush : Bool
  property favor_decompression_speed : Bool

  def initialize(@block_size = LibLZ4::BlockSizeIdT::Max256Kb, @block_mode_linked = true, @checksum = false,
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
