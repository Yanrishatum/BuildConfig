package;

import openfl.display.Sprite;
import openfl.Lib;

/**
 * ...
 * @author Yanrishatum
 */
class Main extends Sprite 
{

	public function new() 
	{
		super();
    trace(TwoMerged.boolValue);
    trace(TwoMerged.subNode.c2_subNodeValue);
    trace(SingleConfig.floatValue2);
    trace(TwoNamed.config2.overridingValue);
		// Assets:
		// openfl.Assets.getBitmapData("img/assetname.jpg");
	}

}
