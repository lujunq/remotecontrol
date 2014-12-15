package art.ciclope.device {
	
	// FLASH PACKAGES
	import flash.events.Event;
	
	/**
	 * SerproxyArduinoEvent provides an event to handle Serproxy connection to an Arduino board.
	 * SerproxyArduinoEvent is distributed under the LGPL v3 license found at https://www.gnu.org/licenses/lgpl-3.0.txt . This means you can use it freely on your own projects - they don't need to be licensed under LGPL, but any changes made to this class itself MUST be released under LGPL.
	 * @author Lucas Junqueira <lucas@ciclope.art.br>
	 */
	public class SerproxyArduinoEvent extends Event {
		
		// PUBLIC CONSTANTS
		
		/**
		 * Output data is available.
		 */
		public static const OUTPUT:String = 'SAEOUTPUT';
		
		/**
		 * Error data is available.
		 */
		public static const ERROR:String = 'SAEERROR';
		
		/**
		 * Process exit data is available.
		 */
		public static const EXIT:String = 'SAEEXIT';
		
		/**
		 * IO error data is available.
		 */
		public static const IOERROR:String = 'SAEIOERROR';
		
		/**
		 * Data received from an Arduino board.
		 */
		public static const DATARECEIVED:String = 'SAEDATARECEIVED';
		
		// PRIVATE VARIABLES
		
		private var _info:String = '';		// event further information
		private var _com:int = -1;			// com port for data received event
		
		/**
		 * SerproxyArduinoEvent constructor.
		 * @param	type	event type
		 * @param	info	further information about the event
		 * @param	com	the com port for data received event (-1 if none)
		 * @param	bubbles	can bubble?
		 * @param	cancelable	is cancelable?
		 */
		public function SerproxyArduinoEvent(type:String, info:String = '', com:int = -1, bubbles:Boolean=false, cancelable:Boolean=false) { 
			super(type, bubbles, cancelable);
			this._info = info.replace("\r", "").replace("\n", "");
			this._com = com;
		}
		
		// READ-ONLY VALUES
		
		/**
		 * Further information about the event.
		 */
		public function get info():String {
			return (this._info);
		}
		
		/**
		 * The com port for data received event (-1 if none).
		 */
		public function get com():int {
			return (this._com);
		}
		
		/**
		 * Clone the current event.
		 * @return	a clone of the current event
		 */
		public override function clone():Event { 
			return new SerproxyArduinoEvent(type, info, com, bubbles, cancelable);
		} 
		
		/**
		 * Event string.
		 * @return	a string representation of the event
		 */
		public override function toString():String { 
			return formatToString("SerproxyArduinoEvent", "type", "info", "com", "bubbles", "cancelable", "eventPhase"); 
		}
		
	}
	
}