package com.bconfig;

import haxe.ds.Either;
import haxe.io.Path;
import haxe.macro.Context;
import haxe.macro.Expr;
import sys.FileSystem;
import sys.io.File;

/**
 * ...
 * @author Yanrishatum
 */
class BuildConfig
{

  #if macro
  
  /**
   * Builds given congurations into class.
   * Important: Build class must be extern.
   * @param configs String or Array of String. Path to configuration files.
   * @param includeConfigName If true, configuration file name will be the root of config nodes. Otherwise builded class will be root of config nodes. Default: false.
   */
  public static function build(configs:Array<String>, includeConfigName:Bool = false):Array<Field>
  {
    var result:Array<Field> = root = new Array();
    // There is separate resource class for each build class. This is done because TypeDefinition can't be changed after Context defined it.
    nodeName = "BCNode" + resourceDefsCount + "_";
    resources = 
    {
      pack: [],
      name: BCResourceClassName + (resourceDefsCount++),
      pos: Context.currentPos(),
      isExtern: false,
      kind: TypeDefKind.TDClass(),
      fields: []
    };
    definitionsCount = 0;
    definitions = new Map();
    
    for (file in configs)
    {
      buildFile(file, includeConfigName, result);
    }
    
    if (resources.fields.length != 0) Context.defineType(resources);
    
    for (def in definitions) Context.defineType(def);
    
    return result;
  }
  
  public static function buildOne(config:String, includeConfigName:Bool = false):Array<Field>
  {
    return build([config], includeConfigName);
  }
  
  /** Amount of resource classes. */
  private static var resourceDefsCount:Int = 0;
  /** Default resource class name. */
  private static inline var BCResourceClassName:String = "BCResources";
  /** Active resource class definition. */
  private static var resources:TypeDefinition;
  /** Current position. Currently only says config name. */
  private static var pos:Position;
  
  /** Node prefix for current build carr */
  private static var nodeName:String;
  
  /** Amount of typedefs in current build call. */
  private static var definitionsCount:Int = 0;
  /** Root injection point. */
  private static var root:Array<Field>;
  /** List of all typedefs. */
  private static var definitions:Map<String, TypeDefinition> = new Map();
  
  /** Builds single configuration file. */
  private static function buildFile(file:String, includeConfigName:Bool, fields:Array<Field>):Void
  {
    var data:Dynamic = getData(file);
    if (data != null)
    {
      pos = Context.makePosition( { min: 0, max: 0, file: file } );
      
      if (includeConfigName)
      {
        insert(new Path(file).file, data, root, []);
      }
      else
      {
        var dataFields:Array<String> = Reflect.fields(data);
        for (field in dataFields)
        {
          insert(field, Reflect.field(data, field), root, []);
        }
      }
    }
  }
  
  private static function getData(file:String):Dynamic
  {
    if (FileSystem.exists(file))
    {
      var ext:String = Path.extension(file);
      var text:String = File.getContent(file);
      
      //switch (ext)
      //{
        //case "xml": 
          //throw "Xml configurations not supported yet."
        //default: // Try to load JSON data by default.
          #if bc_customJson
          var jsonParserName:String = Context.definedValue("bc_customJson");
          var cl:Class<Dynamic> = Type.resolvePath(jsonParserName);
          if (cl != null)
          {
            if (Reflect.hasField(cl, "parse")) return (Reflect.field(cl, "parse"):String->Dynamic)(text);
            else if (Reflect.hasField(cl, "run")) return (Reflect.field(cl, "run"):String->Dynamic)(text);
            else
            {
              throw "Custom Json parser class must have 'parse' or 'run' statuc function of type String->Dynamic";
            }
          }
          else throw "Invalid custom Json parser class name!";
          #elseif (tjson && !bc_notjson)
          return tjson.TJSON.parse(text, file);
          #else
          return haxe.Json.parse(text);
          #end
      //}
    }
    throw "File in path '" + file + "' not found!";
    return null;
  }
  
  private static function insert(name:String, value:Dynamic, target:Array<Field>, path:Array<String>):Void
  {
    if (Std.is(value, String) || Std.is(value, Int) || Std.is(value, Float) || Std.is(value, Bool))
    {
      insertValue(name, value, target, true, target == root);
    }
    else if (Std.is(value, Array))
    {
      // Arrays are not inlied.
      insertValue(name, value, target, false, target == root);
    }
    else
    {
      // __bc_inline: false in config will result in placing object as resource in code instead of inlined structure.
      if (Reflect.hasField(value, "__bc_inline") && Reflect.field(value, "__bc_inline") == false)
      {
        Reflect.deleteField(value, "__bc_inline");
        insertValue(name, value, target, false, target == root);
      }
      else
      {
        var def:TypeDefinition = getTypedef(name, path, target);
        path = path.copy();
        path.push(name);
        
        var subNodes:Array<String> = Reflect.fields(value);
        for (node in subNodes)
        {
          var nodeValue:Dynamic = Reflect.field(value, node);
          insert(node, nodeValue, def.fields, path);
        }
      }
    }
  }
  
  private static function insertValue(name:String, value:Dynamic, target:Array<Field>, isInline:Bool, isStatic:Bool):Void
  {
    if (Std.is(value, Array))
    {
      var fixedArray:Array<Dynamic> = new Array();
      var oldArray:Array<Dynamic> = value;
      for (item in oldArray) fixedArray.push(item);
      value = fixedArray;
    }
    
    var valueExpr:Expr = Context.makeExpr(value, pos);
    var valueType:ComplexType = Context.toComplexType(Context.typeof(valueExpr));
    var resName:String = null;
    
    // Remove overriding.
    checkOverride(name, target);
    
    // Insert property.
    target.push(
    {
      name: name,
      pos: pos,
      doc: (isInline ? "Inlined = " + Std.string(value) : "Non inlined, resource #" + resources.fields.length),
      access: isStatic ? [Access.APublic, Access.AStatic] : [Access.APublic],
      kind: FieldType.FProp("get_" + name, "never", valueType)
    });
    
    // Generating getter function
    var fun:FieldType;
    if (isInline)
    {
      fun = FieldType.FFun(
      {
        args: [],
        ret: valueType,
        expr:
        {
          expr:ExprDef.EReturn(valueExpr),
          pos: pos
        }
      });
    }
    else
    {
      resName = "res_" + resources.fields;
      fun = FieldType.FFun(
      {
        args: [],
        ret: valueType,
        expr:
        {
          expr: ExprDef.EReturn(
          {
            expr: ExprDef.EField(
            {
              expr: ExprDef.EConst(Constant.CIdent(resources.name)),
              pos:pos
            }, resName),
            pos:pos
          }),
          pos:pos
        }
      });
      
      // Inject resource.
      resources.fields.push(
      {
        name: resName,
        access: [Access.APublic, Access.AStatic],
        pos: pos,
        kind: FieldType.FVar(valueType, valueExpr)
      });
    }
    
    // Getter
    target.push({
      name: "get_" + name,
      pos: pos,
      doc: resName,
      access: isStatic ? [Access.APrivate, Access.AStatic, Access.AInline] : [Access.APrivate, Access.AInline],
      kind: fun
    });
  }
  
  private static function checkOverride(name:String, target:Array<Field>):Void
  {
    var i:Int = 0;
    var getName:String = "get_" + name;
    while (i < target.length)
    {
      var field:Field = target[i];
      if (field.name == name)
      {
        target.splice(i, 1);
        continue;
      }
      if (field.name == getName)
      {
        target.splice(i, 1);
        // Remove corresponding resource, if it's not inlined.
        if (field.doc != null)
        {
          for (res in resources.fields)
          {
            if (res.name == field.doc)
            {
              resources.fields.remove(res);
              break;
            }
          }
        }
        continue;
      }
      i++;
    }
  }
  
  private static function insertNode(name:String, node:TypeDefinition, target:Array<Field>, isStatic:Bool = false):Void
  {
    target.push(
    {
      name: name,
      pos: pos,
      access: isStatic ? [Access.APublic, Access.AStatic] : [Access.APublic],
      kind: FieldType.FVar(ComplexType.TPath( { pack:node.pack, name:node.name } ))
    });
  }
  
  private static function getTypedef(name:String, path:Array<String>, target:Array<Field>):TypeDefinition
  {
    var id:String = path.join(".") + "." + name;
    if (definitions.exists(id)) return definitions.get(id);
    
    var def:TypeDefinition =
    {
      pack: ["com", "bconfig", "externs"],
      name: nodeName + (definitionsCount++) + "_" + name,
      pos: pos,
      isExtern: true,
      kind: TypeDefKind.TDClass(),
      fields: []
    };
    insertNode(name, def, target, target == root);
    definitions.set(id, def);
    return def;
  }
  
  #end
  
}