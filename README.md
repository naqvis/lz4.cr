# Crystal LZ4 Compression

Crystal bindings to the [LZ4](https://lz4.github.io/lz4/) compression library. Bindings provided in this shard cover the [frame format](https://github.com/lz4/lz4/blob/dev/doc/lz4_Frame_format.md) as the frame format is recommended one to use and guarantees interoperability with other implementations and language bindings.

LZ4 is lossless compression algorithm, providing compression speed > 500 MB/s per core (>0.15 Bytes/cycle). It features an extremely fast decoder, with speed in multiple GB/s per core (~1 Byte/cycle).

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     lz4:
       github: naqvis/lz4.cr
   ```

2. Run `shards install`

## Usage

```crystal
require "lz4"
```

`LZ4` shard provides both `Compress::LZ4::Reader` and `Compress::LZ4::Writer` as well as `Compress::LZ4#decode` and `Compress::LZ4#encode` methods for quick usage.

## Example: decompress an lz4 file
#
```crystal
require "lz4"

string = File.open("file.lz4") do |file|
   Compress::LZ4::Reader.open(file) do |lz4|
     lz4.gets_to_end
   end
end
pp string
```

## Example: compress to lz4 compression format
#
```crystal
require "lz4"

File.write("file.txt", "abcd")

File.open("./file.txt", "r") do |input_file|
  File.open("./file.lz4", "w") do |output_file|
    Compress::LZ4::Writer.open(output_file) do |lz4|
      IO.copy(input_file, lz4)
    end
  end
end
```


## Contributing

1. Fork it (<https://github.com/naqvis/lz4.cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Ali Naqvi](https://github.com/naqvis) - creator and maintainer
- [Carl Hörberg](https://github.com/carlhoerberg) - creator and maintainer
