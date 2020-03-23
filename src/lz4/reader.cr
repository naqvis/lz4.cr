# A read-only `IO` object to decompress data in the LZ4 frame format.
#
# Instances of this class wrap another IO object. When you read from this instance
# instance, it reads data from the underlying IO, decompresses it, and returns
# it to the caller.
# ## Example: decompress an lz4 file
# ```crystal
# require "lz4"

# string = File.open("file.lz4") do |file|
#    LZ4::Reader.open(file) do |lz4|
#      lz4.gets_to_end
#    end
# end
# pp string
# ```
class LZ4::Reader < IO
  include IO::Buffered

  # If `#sync_close?` is `true`, closing this IO will close the underlying IO.
  property? sync_close : Bool

  # Returns `true` if this reader is closed.
  getter? closed = false

  @context : LibLZ4::Dctx

  # buffer size that avoids execessive round-trips between C and Crystal but doesn't waste too much
  # memory on buffering. Its arbitrarily chosen.
  BUF_SIZE = 64 * 1024

  # Creates an instance of LZ4::Reader.
  def initialize(@io : IO, @sync_close : Bool = false)
    @buffer = Bytes.new(BUF_SIZE)
    @chunk = Bytes.empty

    ret = LibLZ4.create_decompression_context(out @context, LibLZ4::VERSION)
    raise LZ4Error.new("Unable to create lz4 decoder instance: #{String.new(LibLZ4.get_error_name(ret))}") unless LibLZ4.is_error(ret) == 0
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
  def unbuffered_write(slice : Bytes)
    raise IO::Error.new "Can't write to LZ4::Reader"
  end

  def unbuffered_read(slice : Bytes)
    check_open

    return 0 if slice.empty?

    if @chunk.empty?
      m = @io.read(@buffer)
      return m if m == 0
      @chunk = @buffer[0, m]
    end

    loop do
      in_remaining = @chunk.size.to_u64
      out_remaining = slice.size.to_u64

      in_ptr = @chunk.to_unsafe
      out_ptr = slice.to_unsafe

      ret = LibLZ4.decompress(@context, out_ptr, pointerof(out_remaining), in_ptr, pointerof(in_remaining), nil)
      raise LZ4Error.new("lz4 decompression error: #{String.new(LibLZ4.get_error_name(ret))}") unless LibLZ4.is_error(ret) == 0

      @chunk = @chunk[in_remaining..]
      return out_remaining if ret == 0

      if out_remaining == 0
        # Probably ran out of data and buffer needs a refill
        enc_n = @io.read(@buffer)
        return 0 if enc_n == 0
        @chunk = @buffer[0, enc_n]
        next
      end

      return out_remaining
    end
    0
  end

  def unbuffered_flush
    raise IO::Error.new "Can't flush LZ4::Reader"
  end

  # Closes this reader.
  def unbuffered_close
    return if @closed || @context.nil?
    @closed = true

    LibLZ4.free_decompression_context(@context)
    @io.close if @sync_close
  end

  def unbuffered_rewind
    check_open

    @io.rewind
    initialize(@io, @sync_close)
  end

  # :nodoc:
  def inspect(io : IO) : Nil
    to_s(io)
  end
end
