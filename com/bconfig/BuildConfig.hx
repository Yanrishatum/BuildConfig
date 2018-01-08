package com.bconfig;

import haxe.ds.Either;
import haxe.io.Path;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
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
    
    #if bc_debug
    pos = Context.currentPos();
    //resources.fields.push(create__init__(configs, result));
    createReloaders(configs, result);
    #end
    
    for (file in configs)
    {
      buildFile(file, includeConfigName, result);
    }
    //trace(resources.fields.length);
    
    if (resources.fields.length != 0) Context.defineType(resources);
    
    //var i:Int = definitionsList.length - 1;
    //while (i >= 0)
    //{
      //Context.defineType(definitionsList[i]);
      //i--;
    //}
    //Context.defineModule("com.bconfig.externs", definitionsList);
    
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
  //private static var definitionsList:Array<TypeDefinition> = new Array();
  
  private static var includingConfigNames:Bool;
  
  /** Builds single configuration file. */
  private static function buildFile(file:String, includeConfigName:Bool, fields:Array<Field>):Void
  {
    includingConfigNames = includeConfigName;
    var data:Dynamic = getData(file);
    if (data != null)
    {
      pos = Context.makePosition( { min: 0, max: 0, file: file } );
      var filename:String = new Path(file).file;
      if (includeConfigName)
      {
        insert(filename, data, root, [], filename);
      }
      else
      {
        var dataFields:Array<String> = Reflect.fields(data);
        for (field in dataFields)
        {
          insert(field, Reflect.field(data, field), root, [], filename);
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
          #elseif tjson
          if (useTjson()) return tjson.TJSON.parse(text, file);
          else return haxe.Json.parse(text);
          #else
          return haxe.Json.parse(text);
          #end
      //}
    }
    //Context.fatalError("File in path '" + file + "' not found!", Context.makePosition( { min:0, max:0, file: file } ));
    throw "File in path '" + file + "' not found!";
    return null;
  }
  
  #if tjson
  private static function useTjson():Bool
  {
    if (Context.defined("bc_tjson"))
    {
      var val:String = Context.definedValue("bc_tjson");
      return val == "0" || val == "false";
    }
    return true;
  }
  #end
  
  private static function insert(name:String, value:Dynamic, target:Array<Field>, path:Array<String>, configName:String):Void
  {
    if (Std.is(value, String) || Std.is(value, Int) || Std.is(value, Float) || Std.is(value, Bool))
    {
      insertValue(name, value, target, true, target == root, path, configName);
    }
    else if (Std.is(value, Array))
    {
      // Arrays are not inlied.
      insertValue(name, value, target, false, target == root, path, configName);
    }
    else
    {
      // __bc_inline: false in config will result in placing object as resource in code instead of inlined structure.
      if (Reflect.hasField(value, "__bc_inline") && Reflect.field(value, "__bc_inline") == false)
      {
        Reflect.deleteField(value, "__bc_inline");
        insertValue(name, value, target, false, target == root, path, configName);
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
          insert(node, nodeValue, def.fields, path, configName);
        }
      }
    }
  }
  
  #if bc_debug
  
  private static function createReloaders(configs:Array<String>, fields:Array<Field>):Void
  {
    
    var block:Array<Expr> = new Array();
    
    var pos:Position;
    
    for (config in configs)
    {
      var name:String = getResourceName(new Path(config).file);
      pos = Context.makePosition( { min: 0, max: 0, file:"com.bconfig.BuildConfig.hx[reload - "+config+"]" } );
      
      resources.fields.push( {
        name: name,
        pos: pos,
        access: [Access.APublic, Access.AStatic],
        kind: FieldType.FVar(ComplexType.TPath( { pack:[], name:"Dynamic" } ), null)
      });
      
      var line:String;
      
      #if bc_customJson
      var jsonParserName:String = Context.definedValue("bc_customJson");
      var cl:Class<Dynamic> = Type.resolvePath(jsonParserName);
      if (cl != null)
      {
        if (Reflect.hasField(cl, "parse")) line = jsonParserName + ".parse";
        else if (Reflect.hasField(cl, "run")) line = jsonParserName + ".run";
        else line = "haxe.Json.parse";
      }
      #elseif tjson
      if (useTjson()) line = "tjson.TJSON.parse";
      else line = "haxe.Json.parse";
      #else
      line = "haxe.Json.parse";
      #end
      
      line = resources.name + "." + name + " = " + line + "(sys.io.File.getContent(path))";
      
      fields.push({
      name:"reload" + name.substr(0, 1).toUpperCase() + name.substr(1),
      pos: pos,
      access: [Access.APublic, Access.AInline, Access.AStatic],
      kind: FieldType.FFun(
        {
          args: [{ name:"path", type: macro :String }],
          ret: macro :Void,
          expr: macro { $e { Context.parse(line, pos) } }
        })
      });
    }
    
  }
  
  private static function insertValue(name:String, value:Dynamic, target:Array<Field>, isInline:Bool, isStatic:Bool, path:Array<String>, configName:String):Void
  {
    var overrideType:ComplexType;
    
    if (Std.is(value, Array))
    {
      var dynamicType:Bool = false;
      var fixedArray:Array<Dynamic> = new Array();
      var oldArray:Array<Dynamic> = value;
      
      var firstFieldCount:Int = -1;
      var types:Array<Array<Field>> = new Array();
      var baseType:String = null;
      
      for (item in oldArray)
      {
        fixedArray.push(item);
        
        if (!dynamicType)
        {
          var t:ComplexType = Context.toComplexType(Context.typeof(Context.makeExpr(item, pos)));
          switch (t)
          {
            case ComplexType.TAnonymous(fields):
              if (baseType == null) baseType = "--anonymous";
              if (firstFieldCount == -1) firstFieldCount = fields.length;
              else if (firstFieldCount != fields.length || baseType != "--anonymous")
              {
                dynamicType = true;
              }
              types.push(fields);
            case ComplexType.TPath(p):
              var type:String = p.pack.join(".") + "." + p.name;
              if (p.params != null && p.params.length > 0) type += "<" + p.params.join(",") + ">";
              if (p.sub != null)
              {
                if (p.sub == "Int") type += ".Float"; // Allow Int/Float arrays as Float arrays.
                else type += "." + p.sub;
              }
              
              if (baseType == null) baseType = type;
              else if (baseType != type)
              {
                dynamicType = true;
              }
            default:
          }
        }
      }
      value = fixedArray;
      
      if (!dynamicType && baseType == "--anonymous")
      {
        var invalid:Bool = false;
        for (i in 0...fixedArray.length)
        {
          var fields:Array<Field> = types[i];
          for (j in i + 1 ... fixedArray.length)
          {
            var other:Array<Field> = types[j];
            if (!compareStructures(fields, other))
            {
              invalid = true;
              break;
            }
          }
          if (invalid)
          {
            dynamicType = true;
            break;
          }
        }
      }
      
      if (dynamicType)
      {
        var expr:Expr = macro new Array<Dynamic>();
        overrideType = Context.toComplexType(Context.typeof(expr));
      }
    }
    
    var valueExpr:Expr = Context.makeExpr(value, pos);
    var valueType:ComplexType;
    try
    {
      valueType = overrideType != null ? overrideType : Context.toComplexType(Context.typeof(valueExpr));
    }
    catch (e:Dynamic)
    {
      //trace(e);
      valueType = macro :Dynamic;
    }
    
    var resName:String = null;
    
    // Remove old values.
    checkOverride(name, target);
    
    // Insert property.
    target.push(
    {
      name: name,
      pos: pos,
      doc: "Debug path: " + path.join(".") + "." + name,
      access: isStatic ? [Access.APublic, Access.AStatic] : [Access.APublic],
      kind: if (Context.defined("bc_write") && !isInline)
              FieldType.FProp("get", "set", valueType)
            else
              FieldType.FProp("get", "never", valueType)
    });
    
    // Generating getter function
    
    // Getter
    var code:String = "return " + resources.name + ".";
    if (!includingConfigNames) code += getResourceName(configName) + ".";
    if (path.length > 0) code += path.join(".") + ".";
    code += name;
    
    target.push({
      name: "get_" + name,
      pos: pos,
      doc: resName,
      access: isStatic ? [Access.APrivate, Access.AStatic, Access.AInline] : [Access.APrivate, Access.AInline],
      kind: FieldType.FFun(
        {
          args: [],
          ret: valueType,
          expr: Context.parse(code, pos)
        })
    });
    
    if (!isInline && Context.defined("bc_write"))
    {
      target.push( {
        name: "set_" + name,
        pos: pos,
        access: isStatic ? [Access.APrivate, Access.AStatic, Access.AInline] : [Access.APrivate, Access.AInline],
        kind:
          FieldType.FFun(
          {
            args: [ { name: "value", type: valueType } ],
            ret: valueType,
            expr: Context.parse(code + " = value", pos)
          })
      });
    }
  }
  
  private static function getResourceName(configName:String):String
  {
    return ~/[\\\/.]/g.replace(configName, "__");
  }
  
  #else
  
  private static function insertValue(name:String, value:Dynamic, target:Array<Field>, isInline:Bool, isStatic:Bool, path:Array<String>, configName:String):Void
  {
    var overrideType:ComplexType;
    if (Std.is(value, Array))
    {
      var dynamicType:Bool = false;
      var fixedArray:Array<Dynamic> = new Array();
      var oldArray:Array<Dynamic> = value;
      
      var firstFieldCount:Int = -1;
      var types:Array<Array<Field>> = new Array();
      var baseType:String = null;
      
      for (item in oldArray)
      {
        fixedArray.push(item);
        
        if (!dynamicType)
        {
          var t:ComplexType = Context.toComplexType(Context.typeof(Context.makeExpr(item, pos)));
          switch (t)
          {
            case ComplexType.TAnonymous(fields):
              if (baseType == null) baseType = "--anonymous";
              if (firstFieldCount == -1) firstFieldCount = fields.length;
              else if (firstFieldCount != fields.length || baseType != "--anonymous")
              {
                dynamicType = true;
              }
              types.push(fields);
            case ComplexType.TPath(p):
              var type:String = p.pack.join(".") + "." + p.name;
              if (p.params != null && p.params.length > 0) type += "<" + p.params.join(",") + ">";
              if (p.sub != null)
              {
                if (p.sub == "Int") type += ".Float"; // Allow Int/Float arrays as Float arrays.
                else type += "." + p.sub;
              }
              
              if (baseType == null) baseType = type;
              else if (baseType != type)
              {
                dynamicType = true;
              }
            default:
          }
        }
      }
      
      value = fixedArray;
      
      if (!dynamicType && baseType == "--anonymous")
      {
        var invalid:Bool = false;
        for (i in 0...fixedArray.length)
        {
          var fields:Array<Field> = types[i];
          for (j in i + 1 ... fixedArray.length)
          {
            var other:Array<Field> = types[j];
            if (!compareStructures(fields, other))
            {
              invalid = true;
              break;
            }
          }
          if (invalid)
          {
            dynamicType = true;
            break;
          }
        }
      }
      
      if (dynamicType)
      {
        var expr:Expr = macro new Array<Dynamic>();
        overrideType = Context.toComplexType(Context.typeof(expr));
      }
    }
    
    var valueExpr:Expr = Context.makeExpr(value, pos);
    var valueType:ComplexType;
    try
    {
      valueType = overrideType != null ? overrideType : Context.toComplexType(Context.typeof(valueExpr));
    }
    catch (e:Dynamic)
    {
      //trace(e);
      valueType = macro :Dynamic;
    }
    
    var resName:String = null;
    
    // Remove old values.
    checkOverride(name, target);
    
    // Insert property.
    target.push(
    {
      name: name,
      pos: pos,
      doc: (isInline ? "Inlined = " + Std.string(value) : "Non inlined, resource #" + resources.fields.length),
      access: isStatic ? [Access.APublic, Access.AStatic] : [Access.APublic],
      kind: if (Context.defined("bc_write") && !isInline)
              FieldType.FProp("get", "set", valueType)
            else
              FieldType.FProp("get", "never", valueType)
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
      resName = "res_" + resources.fields.length;
      
      fun = FieldType.FFun(
      {
        args: [],
        ret: valueType,
        expr: //macro return ${resources.name}.${resName};
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
      
      if (Context.defined("bc_write"))
      {
        target.push( {
          name: "set_" + name,
          pos: pos,
          access: isStatic ? [Access.APrivate, Access.AStatic, Access.AInline] : [Access.APrivate, Access.AInline],
          kind:
            FieldType.FFun(
            {
              args: [ { name: "value", type: valueType } ],
              ret: valueType,
              expr: //macro return $i{resources.name}.$i{resName} = value;
              {
                expr: ExprDef.EReturn(
                {
                  expr: ExprDef.EBinop(Binop.OpAssign,
                  {
                    expr: ExprDef.EField(
                    {
                      expr: ExprDef.EConst(Constant.CIdent(resources.name)),
                      pos: pos
                    }, resName),
                    pos: pos
                  },
                  {
                    expr: ExprDef.EConst(Constant.CIdent("value")),
                    pos: pos
                  }),
                  pos: pos
                }),
                pos: pos
              }
            })
        });
      }
      
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
  
  #end
  
  private static function compareStructures(first:Array<Field>, second:Array<Field>):Bool
  {
    for (a in first)
    {
      var pair:Field = null;
      for (b in second)
      {
        if (a.name == b.name)
        {
          pair = b;
          break;
        }
      }
      if (pair == null) return false;
      var aType:ComplexType =
      switch (a.kind)
      {
        case FieldType.FVar(t, _): t;
        default: null;
      }
      var bType:ComplexType =
      switch (pair.kind)
      {
        case FieldType.FVar(t, _): t;
        default: null;
      }
      // Quite hacky, but works...
      if (Std.string(aType) != Std.string(bType)) return false;
    }
    return true;
  }
  
  private static function checkOverride(name:String, target:Array<Field>):Void
  {
    var i:Int = 0;
    var getName:String = "get_" + name;
    var setName:String = "set_" + name;
    while (i < target.length)
    {
      var field:Field = target[i];
      if (field.name == name || field.name == setName)
      {
        target.splice(i, 1);
        continue;
      }
      if (field.name == getName)
      {
        target.splice(i, 1);
        // Remove corresponding resource, if it's not inlined.
        #if !bc_debug
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
        #end
        continue;
      }
      i++;
    }
  }
  
  private static function insertNode(name:String, node:TypeDefinition, target:Array<Field>, isStatic:Bool = false):Void
  {
    var path:ComplexType = ComplexType.TPath( { pack: node.pack, name: node.name } );
    target.push(
    {
      name: name,
      pos: pos,
      access: isStatic ? [Access.APublic, Access.AStatic] : [Access.APublic],
      kind: FieldType.FProp("get", "never", path)
    });
    target.push(
    {
      name: "get_" + name,
      pos: pos,
      access: isStatic ? [Access.APrivate, Access.AInline, Access.AStatic] : [Access.APrivate, Access.AInline],
      kind: FieldType.FFun( {
        args: [],
        ret: path,
        expr: macro return null,
        params: []
      })
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
      //isExtern: true,
      kind: TypeDefKind.TDAbstract(ComplexType.TAnonymous([])),
      fields: []
    };
    insertNode(name, def, target, target == root);
    definitions.set(id, def);
    //definitionsList.push(def);
    return def;
  }
  
  #end
  
}