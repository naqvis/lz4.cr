require "./lib"

# A read-only `IO` object to decompress data in the LZ4 frame format.
#
# Instances of this class wrap another IO object. When you read from this instance
# instance, it reads data from the underlying IO, decompresses it, and returns
# it to the caller.
# ## Example: decompress an lz4 file
# ```
# require "lz4"

# string = File.open("file.lz4") do |file|
#    Compress::LZ4::Reader.open(file) do |lz4|
#      lz4.gets_to_end
#    end
# end
# pp string
# ```
class Compress::LZ4::Reader < IO
  property? sync_close : Bool
  getter? closed = false
  @context : LibLZ4::Dctx
  getter compressed_bytes = 0u64
  getter uncompressed_bytes = 0u64

  def compression_ratio : Float64
    return 0.0 if @compressed_bytes.zero?
    @uncompressed_bytes / @compressed_bytes
  end

  def initialize(@io : IO, @sync_close = false)
    ret = LibLZ4.create_decompression_context(out @context, LibLZ4::VERSION)
    raise_if_error(ret, "Failed to create decompression context")
    @buffer = Bytes.new(64 * 1024)
    @buffer_rem = Bytes.empty
  end

  # Creates a new reader from the given *io*, yields it to the given block,
  # and closes it at its end.
  def self.open(io : IO, sync_close : Bool = false)
    reader = new(io, sync_close: sync_close)
    yield reader ensure reader.close
  end

  # Creates a new reader from the given *filename*.
  def self.new(filename : String)
    new(::File.new(filename), sync_close: true)
  end

  # Creates a new reader from the given *io*, yields it to the given block,
  # and closes it at the end.
  def self.open(io : IO, sync_close = false)
    reader = new(io, sync_close: sync_close)
    yield reader ensure reader.close
  end

  # Creates a new reader from the given *filename*, yields it to the given block,
  # and closes it at the end.
  def self.open(filename : String)
    reader = new(filename)
    yield reader ensure reader.close
  end

  # Always raises `IO::Error` because this is a read-only `IO`.
  def write(slice : Bytes) : Nil
    raise IO::Error.new "Can't write to LZ4::Reader"
  end

  def read(slice : Bytes) : Int32
    check_open
    return 0 if slice.empty?

    refill_buffer

    opts = LibLZ4::DecompressOptionsT.new(stable_dst: 0)
    decompressed_bytes = 0
    until @buffer_rem.empty?
      src_remaining = @buffer_rem.size.to_u64
      dst_remaining = slice.size.to_u64

      ret = LibLZ4.decompress(@context, slice, pointerof(dst_remaining), @buffer_rem, pointerof(src_remaining), pointerof(opts))
      raise_if_error(ret, "Failed to decompress")

      @buffer_rem += src_remaining
      slice += dst_remaining
      decompressed_bytes += dst_remaining
      break if slice.empty? # got all we needed
      break if ret.zero?    # ret is a hint of how much more src data is needed
      refill_buffer(ret)
    end
    @uncompressed_bytes &+= decompressed_bytes
    decompressed_bytes
  end

  def flush
    raise IO::Error.new "Can't flush LZ4::Reader"
  end

  def close
    if @sync_close
      @io.close
      @closed = true # Only really closed if io is closed
    end
  end

  def finalize
    LibLZ4.free_decompression_context(@context)
  end

  def rewind
    @io.rewind
    LibLZ4.reset_decompression_context(@context)
  end

  private def refill_buffer(hint = nil)
    return unless @buffer_rem.empty? # never overwrite existing buffer
    if hint
      cnt = @io.read(@buffer[0, Math.min(hint, @buffer.size)])
    else
      cnt = @io.read(@buffer)
    end
    @compressed_bytes &+= cnt
    @buffer_rem = @buffer[0, cnt]
  end

  private def raise_if_error(ret : Int, msg : String)
    if LibLZ4.is_error(ret) != 0
      raise LZ4Error.new("#{msg}: #{String.new(LibLZ4.get_error_name(ret))}")
    end
  end

  # :nodoc:
  def inspect(io : IO) : Nil
    to_s(io)
  end
end
