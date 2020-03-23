# LZ4 Crystal Wrapper
require "semantic_version"

module LZ4
  VERSION = "0.1.0"

  LZ4_VERSION         = SemanticVersion.parse String.new(LibLZ4.version_string)
  LZ4_VERSION_MINIMUM = SemanticVersion.parse("1.9.2")
  raise "unsupported lz4 version #{LZ4_VERSION}, needs #{LZ4_VERSION_MINIMUM} or higher" unless LZ4_VERSION >= LZ4_VERSION_MINIMUM

  class LZ4Error < Exception
  end

  def self.decode(compressed : Slice)
    buf = IO::Memory.new(compressed)
    uncompressed = Reader.open(buf) do |br|
      br.gets_to_end
    end
    uncompressed.to_slice
  end

  def self.encode(content : String)
    encode(content.to_slice)
  end

  def self.encode(content : Slice)
    buf = IO::Memory.new
    Writer.open(buf) do |br|
      br.write content
    end
    buf.rewind
    buf.to_slice
  end
end

require "./**"
