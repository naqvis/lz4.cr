require "./spec_helper"

describe Compress::LZ4 do
  it "can encode and decode" do
    text = "foobar" * 1000
    encoded = Compress::LZ4.encode(text)
    encoded.size.should be < text.bytesize
    decoded = Compress::LZ4.decode(encoded)
    decoded.should eq text.to_slice
  end

  it "can compress" do
    input = IO::Memory.new("foobar" * 100000)
    output = IO::Memory.new
    Compress::LZ4::Writer.open(output) do |lz4|
      IO.copy(input, lz4)
    end
    output.bytesize.should be < input.bytesize
  end

  it "can decompress" do
    bytes = Random::DEFAULT.random_bytes(10 * 1024**2)
    input = IO::Memory.new(bytes)
    compressed = IO::Memory.new
    writer = Compress::LZ4::Writer.new(compressed)
    writer.write bytes
    writer.close

    compressed.rewind

    output = IO::Memory.new
    Compress::LZ4::Reader.open(compressed) do |lz4|
      cnt = IO.copy(lz4, output)
    end
    output.bytesize.should eq bytes.bytesize
    output.to_slice.should eq bytes
  end

  it "can decompress small parts" do
    input = IO::Memory.new("foobar" * 100000)
    output = IO::Memory.new
    Compress::LZ4::Writer.open(output) do |lz4|
      IO.copy(input, lz4)
    end
    output.rewind
    reader = Compress::LZ4::Reader.new(output)
    reader.read_string(6).should eq "foobar"
    reader.close
  end

  it "can stream large amounts" do
    src = "a" * 1024**2
    output = IO::Memory.new
    writer = Compress::LZ4::Writer.new(output)
    writer.write src.to_slice
    output.rewind
    reader = Compress::LZ4::Reader.new(output)
    dst = Bytes.new(1024**2)
    read_count = reader.read(dst)
    read_count.should eq 1024**2
    reader.close
  end

  it "can rewind" do
    src = "a" * 1024**2
    output = IO::Memory.new
    writer = Compress::LZ4::Writer.new(output)
    writer.write src.to_slice
    output.rewind
    reader = Compress::LZ4::Reader.new(output)
    dst = Bytes.new(1024**2)
    read_count = reader.read(dst)
    read_count.should eq 1024**2
    reader.rewind
    read_count = reader.read(dst)
    read_count.should eq 1024**2
    reader.close
  end

  it "can not read more than there is" do
    src = "a"
    output = IO::Memory.new
    writer = Compress::LZ4::Writer.new(output)
    writer.write src.to_slice
    writer.flush
    output.rewind
    reader = Compress::LZ4::Reader.new(output)
    dst = Bytes.new(1024)
    read_count = reader.read(dst)
    read_count.should eq 1
    reader.close
  end

  it "can compress and decompress small parts" do
    rp, wp = IO.pipe
    writer = Compress::LZ4::Writer.new(wp)
    reader = Compress::LZ4::Reader.new(rp)
    writer.print "foo"
    writer.flush
    reader.read_byte.should eq 'f'.ord
    reader.read_byte.should eq 'o'.ord
    reader.read_byte.should eq 'o'.ord
    writer.close
    reader.read_byte.should be_nil
  end

  it "can rewind a reader" do
    input = IO::Memory.new("foobar" * 100000)
    output = IO::Memory.new
    Compress::LZ4::Writer.open(output) do |lz4|
      IO.copy(input, lz4)
    end
    output.rewind
    Compress::LZ4::Reader.open(output) do |lz4|
      lz4.read_byte.should eq 'f'.ord
      lz4.rewind
      lz4.read_byte.should eq 'f'.ord
    end
  end
end
