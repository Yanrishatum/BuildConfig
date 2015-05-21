# BuildConfig
Haxe Macro-based tool for inlining Json configuration files.


`String`, `Int`, `Float` and `Bool` are inlined.

Objects are interpreted as nodes if not said otherwise.

Objects that not nodes and Arrays are not inlined and exists as generated code in BCResource class.

Library supports TJSON library and use it instead of default Haxe json parser until bc_notjson define set.

You can define your own data parser with bc_customJson define, in which you must put a classpath to custom Json parser class.

Custom Json parser class must have `parse` or `run` function with type `String->Dynamic`.

# Api
## `@:build` functions:
`com.bconfig.BuildConfig.build(configs:Array<String>, includeConfigName:Bool = false)` - Build several config files into extern class.

`com.bconfig.BuildConfig.buildOne(config:String, includeConfigName:Bool = false)` - Build one config file into extern class.

`includeConfigName` - If set to `true`, config file name will be used as root node of config file. (e.g. `Config.fileName.value` instead of `Config.value`)

## Json configs meta:
`__bc_inline` - If set to false - Json object in which this value will be inserted as non-inline.

# Usage
```
@:build(com.bconfig.BuildConfig.buildOne("assets/config1.json", false))
extern class SingleConfig { }
```
Note that class must be marked as `extern`, otherwise you'll get a compilation errors.
If you build several configs into one class and don't use independed nodes for files, some values can be overriten by each other.

If you want to put Json Object as non-inlined object, add `"__bc_inline": false` parameter to it.

# Future plans
Sort of hotload feature. Requiring to recompile application every time you change config file while developing is not very comfortable. :)

# Licence
This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or
distribute this software, either in source code form or as a compiled
binary, for any purpose, commercial or non-commercial, and by any
means.

In jurisdictions that recognize copyright laws, the author or authors
of this software dedicate any and all copyright interest in the
software to the public domain. We make this dedication for the benefit
of the public at large and to the detriment of our heirs and
successors. We intend this dedication to be an overt act of
relinquishment in perpetuity of all present and future rights to this
software under copyright law.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

For more information, please refer to <http://unlicense.org>

