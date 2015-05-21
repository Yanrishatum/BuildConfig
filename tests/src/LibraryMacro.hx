package utils;
import haxe.crypto.Crc32;
import haxe.io.Bytes;
import haxe.io.Path;
import haxe.Json;
import haxe.macro.ComplexTypeTools;
import haxe.macro.Context;
import haxe.macro.ExprTools;
import haxe.macro.Type;
import haxe.Serializer;
import haxe.Unserializer;
import haxe.macro.Expr;
#if sys
import sys.io.File;
import sys.FileSystem;
#end
import tjson.TJSON;

/**
 * ...
 * @author Yanrishatum
 */
class LibraryMacro
{

#if macro
  
  private static var nonInlineResources:TypeDefinition = createResourcesDef();
  private static var actualPos:Position;
  private static var defsCount:Int = 0;
  private static var root:Array<Field>;
  private static var defs:Map<String, TypeDefinition> = new Map();
  
  public static function buildLibraries(configs:Array<String>):Array<Field>
  {
    var output:Array<Field> = root = new Array();
    for (config in configs)
    {
      buildLibrary(config, output);
    }
    
    if (nonInlineResources.fields.length > 0) Context.defineType(nonInlineResources);
    for (type in defs.iterator())
    {
      Context.defineType(type);
    }
    return output;
  }
  
  public static function buildLibrary(configName:String, ?output:Array<Field>):Array<Field>
  {
    var doDefine:Bool = false;
    if (output == null)
    {
      doDefine = true;
      output = root = new Array();
    }
    actualPos = Context.makePosition( { min:0, max:1, file:configName } );
    
    var prefix:String = Path.withoutDirectory(configName);
    var config:Dynamic = TJSON.parse(File.getContent(Sys.getCwd() + 'data/${configName}'));
    
    if (nonInlineResources == null) nonInlineResources = createResourcesDef();
    
    var configItems:Array<String> =  Reflect.fields(config);
    for (item in configItems)
    {
      var target:Array<Field> = output;
      var path:Array<String> = new Array();
      var name:String = item;
      if (item.indexOf("/") != -1) // Create nodes
      {
        name = ~/[\-.]/g.replace(Path.withoutExtension(Path.withoutDirectory(item)), '_').toLowerCase();
        var itemPath:Array<String> = ~/[\-.]/g.replace(Path.directory(item), '_').toLowerCase().split("/");
        for (node in itemPath)
        {
          var def:TypeDefinition = createObjectDef(node, path);
          var has:Bool = false;
          for (field in target)
          {
            if (field.name == node)
            {
              has = true;
              
              break;
            }
          }
          if (!has) insertObject(target, node, def, output == target);
          target = def.fields;
          path.push(node);
        }
      }
      insert(target, name, Reflect.field(config, item), path);
    }
    
    if (doDefine)
    {
      if (nonInlineResources.fields.length > 0) Context.defineType(nonInlineResources);
      for (type in defs.iterator())
      {
        Context.defineType(type);
      }
    }
    
    return output;
  }
  
  private static inline function createResourcesDef():TypeDefinition
  {
    return
    {
      pack: [],
      name: "LibraryAssets",
      pos: Context.currentPos(),
      isExtern: false,
      kind: TypeDefKind.TDClass(),
      fields: []
    };
  }
  
  private static function insert(target:Array<Field>, name:String, data:Dynamic, path:Array<String>):Void
  {
    if (Std.is(data, String) || Std.is(data, Int) || Std.is(data, Float) || Std.is(data, Bool)) insertValue(target, name, data, true);
    else if (Std.is(data, Array)) insertValue(target, name, data, false)
    else
    {
      if (Reflect.hasField(data, "__struct"))
      {
        Reflect.deleteField(data, "__struct");
        insertValue(target, name, data, false);
      }
      else
      {
        var def:TypeDefinition = createObjectDef(name, path);
        insertObject(target, name, def, target == root);
        path = path.copy();
        path.push(name);
        
        var fields:Array<String> = Reflect.fields(data);
        for (field in fields)
        {
          var value:Dynamic = Reflect.field(data, field);
          insert(def.fields, field, value, path);
        }
      }
    }
  }
  
  private static function insertValue(target:Array<Field>, name:String, value:Dynamic, isInline:Bool):Void
  {
    if (Std.is(value, Array))
    {
      var fixedArray:Array<Dynamic> = new Array();
      var bugArray:Array<Dynamic> = value;
      for (item in bugArray) fixedArray.push(item);
      value = fixedArray;
    }
    var valueExpr:Expr = Context.makeExpr(value, actualPos);
    var valueType:ComplexType = Context.toComplexType(Context.typeof(valueExpr));
    
    var resName:String = "resource_" + nonInlineResources.fields.length;
    // property
    target.push({
      name: name,
      pos: actualPos,
      doc: (isInline ? "Inlined" : "Non inlined, resource #" + nonInlineResources.fields.length + ": " + name),
      access: [Access.APublic],
      kind: FieldType.FProp("get_" + name, "never", valueType )
    });
    // Inline
    if (isInline)
    {
      target.push({
        name: "get_" + name,
        pos: actualPos,
        access: [Access.APrivate, Access.AInline],
        kind: FieldType.FFun({ args: [], ret: valueType, expr: { expr:ExprDef.EReturn(valueExpr), pos:actualPos } })
      });
    }
    else
    {
      nonInlineResources.fields.push({
        name: resName,
        access: [Access.APublic, Access.AStatic],
        pos: actualPos,
        kind: FieldType.FVar(valueType, valueExpr)
      });
      target.push({
        name: "get_"+name,
        pos: actualPos,
        access: [Access.APrivate, Access.AInline],
        kind: FieldType.FFun({ args: [], ret: valueType, expr: { expr:ExprDef.EReturn({ expr:ExprDef.EField({ expr: ExprDef.EConst(Constant.CIdent("LibraryAssets")), pos:actualPos }, resName), pos:actualPos }), pos:actualPos } })
      });
    }
  }
  
  private static function createObjectDef(name:String, path:Array<String>):TypeDefinition
  {
    var defId:String = path.join("//") + "//" + name;
    if (defs.exists(defId)) return defs.get(defId);
    
    var def:TypeDefinition =
    {
      pack: ["auto", "utils"],
      name: "InlineAsset_" + (defsCount++) + "_" + name,
      pos: actualPos,
      isExtern: true,
      kind: TypeDefKind.TDClass(),
      fields: []
    };
    defs.set(defId, def);
    return def;
  }
  
  private static function insertObject(target:Array<Field>, name:String, def:TypeDefinition, isStatic:Bool = false):Void
  {
    target.push(
    {
      name: name,
      pos: actualPos,
      access: isStatic ? [Access.APublic, Access.AStatic] : [Access.APublic],
      kind: FieldType.FVar(ComplexType.TPath( { pack:def.pack, name:def.name } ))
    });
  }
  
#end
}
