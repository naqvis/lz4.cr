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

  def initialize(@io : IO, @sync_close = false)
    ret = LibLZ4.create_decompression_context(out @context, LibLZ4::VERSION)
    raise_if_error(ret, "Failed to create decompression context")
    @buffer = Bytes.new(DEFAULT_BUFFER_SIZE)
    @chunk = Bytes.empty
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

  def read(slice : Bytes) : Int
    check_open
    return 0 if slice.empty?

    refill_buffer if @chunk.empty?

    opts = LibLZ4::DecompressOptionsT.new(stable_dst: 1)
    decompressed_bytes = 0
    loop do
      src_remaining = @chunk.size.to_u64
      dst_remaining = slice.size.to_u64

      ret = LibLZ4.decompress(@context, slice, pointerof(dst_remaining), @chunk, pointerof(src_remaining), pointerof(opts))
      raise_if_error(ret, "Failed to decompress")

      @chunk = @chunk + src_remaining
      slice = slice + dst_remaining
      decompressed_bytes += dst_remaining
      break if slice.empty?        # got all we needed
      break if dst_remaining.zero? # didn't progress
      STDERR.puts "hint=#{ret}"
      refill_buffer if ret > 0 # ret is a hint of how much more src data is needed
    end
    decompressed_bytes
  end

  def flush
    raise IO::Error.new "Can't flush LZ4::Reader"
  end

  def close
    check_open
    @closed = true
    @io.close if @sync_close
  end

  def finalize
    LibLZ4.free_decompression_context(@context)
  end

  def rewind
    @io.rewind
    LibLZ4.reset_decompression_context(@context)
  end

  private def refill_buffer
    cnt = @io.read(@buffer)
    STDERR.puts "refilling buffer, got=#{cnt}"
    @chunk = @buffer[0, cnt]
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
