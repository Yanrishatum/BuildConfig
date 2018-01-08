package;

/**
 * ...
 * @author 
 */
extern class JustTest
{

  public static inline var otherjust_vars:String = "123";
  
  public static var something:OtherJust;
  
  public function new() {}
  
}

extern class OtherJust
{
  public var vars(get, never):String;
  public inline function get_vars():String { return JustTest.otherjust_vars; }
}