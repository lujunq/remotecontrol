package paradoxo {
	import flash.net.Socket;
	
	/**
	 * ...
	 * @author Lucas Junqueira
	 */
	public class TabletData {
		
		public var id:int = -1;
		public var socket:Socket;
		public var ready:Boolean = false;
		
		public function TabletData(id:int) {
			this.id = id;
		}
		
	}

}