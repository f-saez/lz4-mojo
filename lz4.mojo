
import sys.ffi
from memory.unsafe_pointer import UnsafePointer
from random import randint
from testing.testing import assert_true
from collections import Optional

alias LZ4_versionNumber = fn() -> UInt32
alias LZ4_compress_default = fn(UnsafePointer[UInt8], UnsafePointer[UInt8], Int, Int) -> Int
alias LZ4_decompress_safe = fn(UnsafePointer[UInt8], UnsafePointer[UInt8], Int, Int) -> Int
alias LZ4_compress_HC = fn(UnsafePointer[UInt8], UnsafePointer[UInt8], Int, Int, Int) -> Int
alias LZ4_compressBound = fn(Int32) -> Int

alias LZ4HC_CLEVEL_MIN     =  2
alias LZ4HC_CLEVEL_DEFAULT =  9
alias LZ4HC_CLEVEL_OPT_MIN = 10
alias LZ4HC_CLEVEL_MAX     = 12

alias LIBNAME = "liblz4.so"

@value
struct LZ4Version(Stringable):
    var major: UInt32
    var minor: UInt32
    var version: UInt32

    fn __init__(inout self, v : UInt32):
        self.major = v/(100*100)
        self.minor = (v/100) - (self.major*100)
        self.version = v - (self.major*100*100) - (self.minor*100)
    
    fn __str__(self) -> String:
        return String(self.major)+"."+String(self.minor)+"."+String(self.version)
    
@value
struct LZ4:
    var _handle : ffi.DLHandle

    fn __init__(inout self):
        self._handle = ffi.DLHandle(LIBNAME, ffi.RTLD.NOW)

    @staticmethod
    fn new() -> Optional[Self]:
        var result = Optional[Self](None)
        var handle = ffi.DLHandle(LIBNAME, ffi.RTLD.NOW)
        if handle.__bool__():
            result = Optional[Self]( Self(handle) )
        else:
            print("Unable to load ",LIBNAME)
        return result

    fn version(self) -> LZ4Version:
        var num = self._handle.get_function[LZ4_versionNumber]("LZ4_versionNumber")()
        return LZ4Version(num)

    fn compress_bound(self, input_size : Int) -> Int:
        """
        LZ4_compressBound() :
            Provides the maximum size that LZ4 compression may output in a "worst case" scenario (input data not compressible).
            This function is primarily useful for memory allocation purposes (destination buffer size).            
            Note that LZ4_compress_default() compresses faster when dstCapacity is >= LZ4_compressBound(srcSize)
            inputSize  : max supported value is LZ4_MAX_INPUT_SIZE
            return : maximum output size in a "worst case" scenario or 0, if input size is incorrect (too large or negative).
        """
        return self._handle.get_function[LZ4_compressBound]("LZ4_compressBound")(input_size)
    
    @always_inline
    fn min_comp_level(self) -> Int:
        return LZ4HC_CLEVEL_MIN
    
    @always_inline
    fn max_comp_level(self) -> Int:
        return LZ4HC_CLEVEL_MAX
    
    @always_inline
    fn default_level(self) -> Int:
        return LZ4HC_CLEVEL_DEFAULT

    fn compress_default(self, src : List[UInt8], inout dst : List[UInt8]) -> Bool:
        """ 
        LZ4_compress_default() :
        Compresses 'srcSize' bytes from 'src' into already allocated 'dst'.
        Compression is guaranteed to succeed if 'dstCapacity' >= LZ4_compressBound(srcSize).
        It also runs faster, so it's a recommended setting.
        If the function cannot compress 'src' into a more limited 'dst' budget,
        compression stops *immediately*, and the function result is False.
        In which case, 'dst' content is undefined (invalid).
        """        
        var l = self._handle.get_function[LZ4_compress_default]("LZ4_compress_default")(src.unsafe_ptr(), dst.unsafe_ptr(), src.size, dst.size)
        if l>0:
            dst.resize(l)
        return l>0
        
    fn compress_hc(self, src : List[UInt8], inout dst : List[UInt8], compression_level: Int) -> Int:
        """ 
        LZ4_compress_HC() :
            Compress data from `src` into `dst`, using the powerful but slower "HC" algorithm.
            `dst` must be already allocated.
            Compression is guaranteed to succeed if `dstCapacity >= LZ4_compressBound(srcSize)` (see "lz4.h")
            Max supported `srcSize` value is LZ4_MAX_INPUT_SIZE (see "lz4.h")
            `compressionLevel` : any value between 1 and LZ4HC_CLEVEL_MAX will work.
                                Values > LZ4HC_CLEVEL_MAX behave the same as LZ4HC_CLEVEL_MAX.
            @return : the number of bytes written into 'dst' or 0 if compression fails.
        """   
        var cl:Int
        if compression_level<LZ4HC_CLEVEL_MIN:
            cl = LZ4HC_CLEVEL_MIN
        elif compression_level>LZ4HC_CLEVEL_MAX:
            cl = LZ4HC_CLEVEL_MAX
        else:
            cl = compression_level
        return self._handle.get_function[LZ4_compress_HC]("LZ4_compress_HC")(src.unsafe_ptr(), dst.unsafe_ptr(), src.size, dst.size, cl)

    fn decompress_safe(self, src : List[UInt8], inout dst : List[UInt8], uncompressed_size : Int) -> Bool:
        """ 
        LZ4_decompress_safe() :
            Decompress data from `src` into already allocated `dst`
            uncompressed_size : exact size of the decompressed data
            @return : False if something went wrong during decompression.
        """        
        dst.resize(uncompressed_size, 0)
        var l = self._handle.get_function[LZ4_decompress_safe]("LZ4_decompress_safe")(src.unsafe_ptr(), dst.unsafe_ptr(), src.size, dst.size)
        return l==uncompressed_size      
    
    @staticmethod
    fn validation() raises:
        """
          Yeah, I know. This should be in a file in test directory.
          I'll do that later.
        """
        fn compare_list(a : List[UInt8], b : List[UInt8]) raises -> Bool:
            assert_true(a.size==b.size,"size error")
            for idx in range(0,a.size):
                assert_true(a[idx]==b[idx],"value error")
            return True

        var original = List[UInt8]()
        original.resize(16384,0)
        var lz4 = LZ4()
        var recommended_size = lz4.compress_bound(original.size)
        assert_true(recommended_size>original.size,"error while calling compress_bound")

        var compressed = List[UInt8]()
        var uncompress = List[UInt8]()

        # first shot, best case : an easy to compressed file
        compressed.resize(recommended_size,0)
        var result = lz4.compress_default(original, compressed)
        assert_true(result,"error while compressing")
        assert_true(compressed.size<original.size,"error while compressing")
        result = lz4.decompress_safe(compressed, uncompress, original.size)
        assert_true(result,"size error")        
        assert_true(compare_list(original,uncompress),"result is not the same as source")

        # then with compress_hc
        compressed.resize(recommended_size,0)
        var result_hc = lz4.compress_hc(original, compressed, LZ4HC_CLEVEL_MAX)
        assert_true(result_hc>0,"error while compressing")
        assert_true(result_hc<original.size,"error while compressing")
        compressed.resize(result_hc)
        result = lz4.decompress_safe(compressed, uncompress, original.size)
        assert_true(result,"decompress / size error")
        assert_true(compare_list(original,uncompress),"result is not the same as source")

        # second shot, worst case : just noise
        var p = DTypePointer[DType.uint8](original.unsafe_ptr())
        randint[DType.uint8](p, original.size, 0, 255)
        # a compressed file is usually smaller than the original, but we are compressing pure noise
        # so we should expect a bigger file, but not biggeer than the recommended size
        compressed.resize(recommended_size,0)
        result = lz4.compress_default(original, compressed)
        assert_true(result,"error while compressing noise")
        assert_true(compressed.size>original.size,"error while compressing noise")
        result = lz4.decompress_safe(compressed, uncompress, original.size)
        assert_true(result,"decompress noise / size error")
        assert_true(compare_list(original,uncompress),"result is not the same as source")
        
        # then with compress_hc
        compressed.resize(recommended_size,0)
        result_hc = lz4.compress_hc(original, compressed, LZ4HC_CLEVEL_MAX)
        assert_true(result_hc>0,"error while compressing")
        assert_true(result,"error while compressing noise")
        compressed.resize(result_hc)
        result = lz4.decompress_safe(compressed, uncompress, original.size)
        assert_true(result,"decompress noise / size error")
        assert_true(compare_list(original,uncompress),"result is not the same as source")
                      
fn main() raises :
    LZ4.validation()
    

    



    
