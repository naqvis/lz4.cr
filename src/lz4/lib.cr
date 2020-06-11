module Compress::LZ4
  @[Link(ldflags: "`command -v pkg-config > /dev/null && pkg-config --libs liblz4 2> /dev/null|| printf %s '--llz4'`")]
  lib LibLZ4
    alias ErrorCodeT = LibC::SizeT
    alias Uint32T = LibC::UInt
    alias Uint16T = LibC::UShort
    alias Uint8T = UInt8

    VERSION_MAJOR   =          1
    VERSION_MINOR   =          9
    VERSION_RELEASE =          2
    MEMORY_USAGE    =         14
    MAX_INPUT_SIZE  = 2113929216

    CLEVEL_MIN     =  3
    CLEVEL_DEFAULT =  9
    CLEVEL_OPT_MIN = 10
    CLEVEL_MAX     = 12

    DICTIONARY_LOGSIZE = 16
    HASH_LOG           = 15

    VERSION                        = 100
    HEADER_SIZE_MIN                =   7
    HEADER_SIZE_MAX                =  19
    BLOCK_HEADER_SIZE              =   4
    BLOCK_CHECKSUM_SIZE            =   4
    CONTENT_CHECKSUM_SIZE          =   4
    MIN_SIZE_TO_KNOW_HEADER_LENGTH =   5

    fun version_number = LZ4_versionNumber : LibC::Int
    fun version_string = LZ4_versionString : LibC::Char*

    # makes it possible to supply advanced compression instructions to streaming interface.
    # Structure must be first init to 0, using memset() or LZ4F_INIT_PREFERENCES,
    # setting all parameters to default.
    # All reserved fields must be set to zero.
    struct PreferencesT
      frame_info : FrameInfoT
      compression_level : LibC::Int
      auto_flush : LibC::UInt
      favor_dec_speed : LibC::UInt
      reserved : LibC::UInt[3]
    end

    struct FrameInfoT
      block_size_id : BlockSizeIdT
      block_mode : BlockModeT
      content_checksum_flag : ContentChecksumT
      frame_type : FrameTypeT
      content_size : LibC::ULongLong
      dict_id : LibC::UInt
      block_checksum_flag : BlockChecksumT
    end

    enum BlockSizeIdT
      Default  = 0
      Max64Kb  = 4
      Max256Kb = 5
      Max1Mb   = 6
      Max4Mb   = 7
    end
    enum BlockModeT
      BlockLinked      = 0
      BlockIndependent = 1
    end
    enum ContentChecksumT
      NoContentChecksum      = 0
      ContentChecksumEnabled = 1
    end
    enum FrameTypeT
      Frame          = 0
      SkippableFrame = 1
    end
    enum BlockChecksumT
      NoBlockChecksum      = 0
      BlockChecksumEnabled = 1
    end

    # Error management
    fun is_error = LZ4F_isError(code : ErrorCodeT) : LibC::UInt
    fun get_error_name = LZ4F_getErrorName(code : ErrorCodeT) : LibC::Char*

    # Simple compression function
    fun compress_frame_bound = LZ4F_compressFrameBound(src_size : LibC::SizeT, preferences_ptr : PreferencesT*) : LibC::SizeT
    fun compress_frame = LZ4F_compressFrame(dst_buffer : Void*, dst_capacity : LibC::SizeT, src_buffer : Void*, src_size : LibC::SizeT, preferences_ptr : PreferencesT*) : LibC::SizeT

    # Compression Resource management
    type Cctx = Void*
    fun create_compression_context = LZ4F_createCompressionContext(cctx_ptr : Cctx*, version : LibC::UInt) : ErrorCodeT
    fun free_compression_context = LZ4F_freeCompressionContext(cctx : Cctx) : ErrorCodeT

    # Compression
    struct CompressOptionsT
      stable_src : LibC::UInt
      reserved : LibC::UInt[3]
    end

    fun compress_begin = LZ4F_compressBegin(cctx : Cctx, dst_buffer : Void*, dst_capacity : LibC::SizeT, prefs_ptr : PreferencesT*) : LibC::SizeT
    fun compress_bound = LZ4F_compressBound(src_size : LibC::SizeT, prefs_ptr : PreferencesT*) : LibC::SizeT
    fun compress_update = LZ4F_compressUpdate(cctx : Cctx, dst_buffer : Void*, dst_capacity : LibC::SizeT, src_buffer : Void*, src_size : LibC::SizeT, c_opt_ptr : CompressOptionsT*) : LibC::SizeT
    fun flush = LZ4F_flush(cctx : Cctx, dst_buffer : Void*, dst_capacity : LibC::SizeT, c_opt_ptr : CompressOptionsT*) : LibC::SizeT
    fun compress_end = LZ4F_compressEnd(cctx : Cctx, dst_buffer : Void*, dst_capacity : LibC::SizeT, c_opt_ptr : CompressOptionsT*) : LibC::SizeT

    # Decompression Resource Management
    type Dctx = Void*
    fun create_decompression_context = LZ4F_createDecompressionContext(dctx_ptr : Dctx*, version : LibC::UInt) : ErrorCodeT
    fun free_decompression_context = LZ4F_freeDecompressionContext(dctx : Dctx) : ErrorCodeT

    # Streaming Decompression Function
    struct DecompressOptionsT
      stable_dst : LibC::UInt
      reserved : LibC::UInt[3]
    end

    fun header_size = LZ4F_headerSize(src : Void*, src_size : LibC::SizeT) : LibC::SizeT
    fun get_frame_info = LZ4F_getFrameInfo(dctx : Dctx, frame_info_ptr : FrameInfoT*, src_buffer : Void*, src_size_ptr : LibC::SizeT*) : LibC::SizeT
    fun decompress = LZ4F_decompress(dctx : Dctx, dst_buffer : Void*, dst_size_ptr : LibC::SizeT*, src_buffer : Void*, src_size_ptr : LibC::SizeT*, d_opt_ptr : DecompressOptionsT*) : LibC::SizeT
    fun reset_decompression_context = LZ4F_resetDecompressionContext(dctx : Dctx)
  end
end
