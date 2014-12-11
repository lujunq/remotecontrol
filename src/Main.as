package {
	import art.ciclope.display.QRCodeDisplay;
	import art.ciclope.event.TCPDataEvent;
	import art.ciclope.handle.WEBROOTManager;
	import art.ciclope.net.HTTPServer;
	import art.ciclope.net.JSONTCPServer;
	import art.ciclope.net.WebSocketsServer;
	import flash.display.StageDisplayState;
	
	import flash.desktop.NativeApplication;
	import flash.events.Event;
	import flash.display.Sprite;
	import flash.display.StageAlign;
	import flash.display.StageScaleMode;
	import flash.ui.Multitouch;
	import flash.ui.MultitouchInputMode;
	
	/**
	 * ...
	 * @author Lucas Junqueira
	 */
	public class Main extends Sprite {
		
		public static var content:Sprite;
		
		private const WEBSERVERPORT:uint = 8080;
		private const WEBSOCKETPORT:uint = 8087;
		private const DESIGNWIDTH:uint = 1280;
		private const DESIGNHEIGHT:uint = 720;
		private const TCPPORT:uint = 8765;
		
		private var _webroot:WEBROOTManager;
		private var _tcpServer:JSONTCPServer;
		private var _qrCode:QRCodeDisplay;
		private var _webServer:HTTPServer;
		private var _webSocket:WebSocketsServer;
		
		
		public function Main():void {
			stage.scaleMode = StageScaleMode.NO_SCALE;
			stage.align = StageAlign.TOP_LEFT;
			stage.addEventListener(Event.DEACTIVATE, deactivate);
			stage.displayState = StageDisplayState.FULL_SCREEN_INTERACTIVE;
			
			// touch or gesture?
			Multitouch.inputMode = MultitouchInputMode.TOUCH_POINT;
			
			// prepare webroot files
			this._webroot = new WEBROOTManager('webroot', false);
			this._webroot.addEventListener(Event.COMPLETE, onWebrootComplete);
		}
		
		private function onWebrootComplete(evt:Event):void {
			// start tcp server
			this._tcpServer = new JSONTCPServer();
			this._tcpServer.start(this.TCPPORT);
			this._tcpServer.addEventListener(TCPDataEvent.RECEIVED, onJSONMessage);
			
			// prepare web server
			this._webServer = new HTTPServer();
			this._webServer.start(this.WEBSERVERPORT, this._webroot.webroot);
			
			// prepare web sockets server
			this._webSocket = new WebSocketsServer();
			this._webSocket.addEventListener(Event.COMPLETE, onWebsocketsComplete);
			this._webSocket.addEventListener(TCPDataEvent.RECEIVED, onWebSocketsReceived);
			this._webSocket.bind(this._tcpServer.serverActiveIPv4[0], this.WEBSOCKETPORT);
		}
		
		private function onWebsocketsComplete(evt:Event):void {
			// write websockets configuration file
			this._webroot.writeFile('config.js', "var webSocketAddress = '" + this._webSocket.serverAddress + "';\n");
			
			// prepare display
			Main.content = new Sprite();
			Main.content.graphics.beginFill(0xCCCCCC);
			Main.content.graphics.drawRect(0, 0, this.DESIGNWIDTH, this.DESIGNHEIGHT);
			Main.content.graphics.endFill();
			Main.content.width = stage.stageWidth;
			Main.content.scaleY = Main.content.scaleX;
			if (Main.content.height > stage.stageHeight) {
				Main.content.height = stage.stageHeight;
				Main.content.scaleX = Main.content.scaleY;
			}
			Main.content.x = (stage.stageWidth - Main.content.width) / 2;
			Main.content.y = (stage.stageHeight - Main.content.height) / 2;
			this.addChild(Main.content);
			
			// show connection address using qr code
			this._qrCode = new QRCodeDisplay();
			Main.content.addChild(this._qrCode);
			this._qrCode.setCode(this._webServer.serverAddress(this._tcpServer.serverActiveIPv4[0]) + '/remote.html');
			trace(this._qrCode.code);
		}
		
		private function onJSONMessage(evt:TCPDataEvent):void {
			this._tcpServer.sendJSONToClient(evt.messageData, evt.client);
		}
		
		private function onWebSocketsReceived(evt:TCPDataEvent):void {
			
		}
		
		private function deactivate(e:Event):void {
			// NativeApplication.nativeApplication.exit();
		}
		
	}
	
}