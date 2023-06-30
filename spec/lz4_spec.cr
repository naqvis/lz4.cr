require "./spec_helper"

describe Compress::LZ4 do
  it "can compress" do
    input = IO::Memory.new("foobar" * 100000)
    output = IO::Memory.new
    Compress::LZ4::Writer.open(output) do |lz4|
      IO.copy(input, lz4)
    end
    output.bytesize.should be < input.bytesize
  end

  it "can decompress" do
    src_str = "foobar" * 100000
    input = IO::Memory.new(src_str)
    compressed = IO::Memory.new
    Compress::LZ4::Writer.open(compressed) do |lz4|
      cnt = IO.copy(input, lz4)
      puts "wrote #{cnt} bytes"
    end
    compressed.rewind

    output = IO::Memory.new
    Compress::LZ4::Reader.open(compressed) do |lz4|
      cnt = IO.copy(lz4, output)
      puts "read #{cnt} bytes"
    end
    str = output.to_s
    str.bytesize.should eq src_str.bytesize
    str.should eq src_str
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

  it "should raise if not fully decompressed on close" do
    src = "a" * 1024**2
    output = IO::Memory.new
    writer = Compress::LZ4::Writer.new(output)
    writer.write src.to_slice
    output.rewind
    reader = Compress::LZ4::Reader.new(output)
    dst = Bytes.new(1024)
    read_count = reader.read(dst)
    reader.close
  end
end
