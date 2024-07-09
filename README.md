    # lz4-mojo
LZ4 bindings for Mojo

# What is LZ4 ?
https://github.com/lz4/lz4

# How to use it ?

```
# let's say original is a bunch of bytes we need to compress
var original = List[UInt8]()
original.resize(16384,0)
var aa = LZ4.new() # aa is an Optional
if aa:
    var lz4 = aa.take()
    var recommended_size = lz4.compress_bound(original.size)
    var compressed = List[UInt8]() # will contains the compressed data
    compressed.resize(recommended_size,0)
    if lz4.compress_default(original, compressed):
        # that's it.
        # now the reverse operation
        var uncompress = List[UInt8]()
        if lz4.decompress_safe(compressed, uncompress, original.size):
            print("Done !")
```

Need a little bit more compression ? replace
```
lz4.compress_default(original, compressed)
```
by
```
lz4.compress_hc(original, compressed, LZ4HC_CLEVEL_MAX)
```


