package {
	import art.ciclope.data.PersistentData;
	import art.ciclope.device.SerproxyArduino;
	import art.ciclope.device.SerproxyArduinoEvent;
	import art.ciclope.display.QRCodeDisplay;
	import art.ciclope.event.TCPDataEvent;
	import art.ciclope.handle.WEBROOTManager;
	import art.ciclope.net.HTTPServer;
	import art.ciclope.net.JSONTCPServer;
	import art.ciclope.net.WebSocketsServer;
	import flash.display.StageDisplayState;
	import flash.net.Socket;
	import paradoxo.TabletData;
	
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
		public static var config:PersistentData;
		
		public static const DEBUG:Boolean = true;
		
		private const WEBSERVERPORT:uint = 8080;
		private const WEBSOCKETPORT:uint = 8087;
		private const DESIGNWIDTH:uint = 1280;
		private const DESIGNHEIGHT:uint = 720;
		private const TCPPORT:uint = 8765;
		private const NUMTABLETS:uint = 4;
		
		private var _webroot:WEBROOTManager;
		private var _tcpServer:JSONTCPServer;
		private var _qrCode:QRCodeDisplay;
		private var _webServer:HTTPServer;
		private var _webSocket:WebSocketsServer;
		
		private var _tablets:Vector.<TabletData>;
		private var _currentID:int;
		private var _arduino:SerproxyArduino;
		
		
		public function Main():void {
			stage.scaleMode = StageScaleMode.NO_SCALE;
			stage.align = StageAlign.TOP_LEFT;
			stage.addEventListener(Event.DEACTIVATE, deactivate);
			if (!Main.DEBUG) stage.displayState = StageDisplayState.FULL_SCREEN_INTERACTIVE;
			
			// config
			Main.config = new PersistentData('remotecontrol', 'config');
			
			// touch or gesture?
			Multitouch.inputMode = MultitouchInputMode.TOUCH_POINT;
			
			// prepare webroot files
			this._webroot = new WEBROOTManager('webroot', false);
			this._webroot.addEventListener(Event.COMPLETE, onWebrootComplete);
			
			// prepare system
			this._tablets = new Vector.<TabletData>();
			for (var index:uint = 0; index < this.NUMTABLETS; index++) {
				this._tablets.push(new TabletData(index));
			}
			this._currentID = 0;
			
			// configuration
			if (!Main.config.isSet('arduinocom')) Main.config.setValue('arduinocom', '4');
			if (!Main.config.isSet('arduinoport')) Main.config.setValue('arduinoport', '10014');
			if (!Main.config.isSet('arduinobaud')) Main.config.setValue('arduinobaud', '9600');
			
			// arduino
			this._arduino = new SerproxyArduino();
			this._arduino.restartOnExit = true;
			this._arduino.addEventListener(SerproxyArduinoEvent.DATARECEIVED, onSPData);
			this._arduino.addArduino(uint(Main.config.getValue('arduinocom')), uint(Main.config.getValue('arduinoport')), uint(Main.config.getValue('arduinobaud')));
			this._arduino.start();
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
			this._qrCode.setCode(this._webServer.serverAddress(this._tcpServer.serverActiveIPv4[0]) + '/abelhas/abelha.html');
			trace(this._qrCode.code);
		}
		
		private function onJSONMessage(evt:TCPDataEvent):void {
			if (!this.processMessage(evt.messageData, evt.client)) {
				this._tcpServer.sendJSONToClient({ "ac":"erro", "original":evt.messageData.ac }, evt.client);
			}
		}
		
		private function onWebSocketsReceived(evt:TCPDataEvent):void {
			if (evt.messageData != null) {
				if (evt.messageData.ac != null) {
					switch (String(evt.messageData.ac)) {
						case 'bee':
							var pos:uint = uint(Math.round(100 * Number(evt.messageData.height) / Number(evt.messageData.total)));
							if (this._tablets[0].ready) {
								this._tcpServer.sendJSONToClient( { 'ac':'abelha', 'altura': pos }, this._tablets[0].socket);
							}
							break;
					}
				}
			}
		}
		
		private function deactivate(e:Event):void {
			// NativeApplication.nativeApplication.exit();
		}
		
		private function processMessage(message:Object, client:Socket):Boolean {
			var ret:Boolean = false;
			if (message.ac != null) {
				var resposta:Object = new Object();
				var i:uint;
				var to:int;
				switch (String(message.ac)) {
					case 'hi':
						if (message.numero != null) {
							var numero:int = int(message.numero);
							if ((numero >= 0) && (numero < this.NUMTABLETS)) {
								this._tablets[numero].socket = client;
								this._tablets[numero].ready = true;
								ret = true;
							}
						}
						break;
					case 'newid':
						resposta.ac = "objid";
						resposta.numero = int(this._currentID);
						this._tcpServer.sendJSONToClient(resposta, client);
						this._currentID++;
						ret = true;
						break;
					case 'resend':
						if (message.tablet != null) {
							to = int (message.tablet);
							if (to < this.NUMTABLETS) {
								if (this._tablets[to].ready) {
									this._tcpServer.sendJSONToClient(message, this._tablets[to].socket);
									ret = true;
								}
							} else {
								for (i = 0; i < this.NUMTABLETS; i++) {
									if (this._tablets[i].socket != client) {
										this._tcpServer.sendJSONToClient(message, this._tablets[i].socket);
									}
								}
								ret = true;
							}
						}
						break;
					case 'resetids':
						this._currentID = 0;
						ret = true;
						break;
					case 'objeto':
						if (message.para != null) {
							to = int (message.para);
							if (to < this.NUMTABLETS) {
								if (this._tablets[to].ready) {
									this._tcpServer.sendJSONToClient(message, this._tablets[to].socket);
									ret = true;
								}
							} else {
								for (i = 0; i < this.NUMTABLETS; i++) {
									if (this._tablets[i].socket != client) {
										this._tcpServer.sendJSONToClient(message, this._tablets[i].socket);
									}
								}
								ret = true;
							}
						}
						break;
				}
			}
			
			return (ret);
		}
		private function sendToArduino(message:String):void {
			if (this._arduino != null) this._arduino.sendToArduino(uint(Main.config.getValue('arduinocom')), message);
		}
		
		private function onSPData(evt:SerproxyArduinoEvent):void {
			switch (evt.info) {
				default:
					break;
			}
		}
	}
	
}