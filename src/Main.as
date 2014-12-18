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
	import flash.display.Loader;
	import flash.display.StageDisplayState;
	import flash.net.Socket;
	import flash.net.URLRequest;
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
		
		public static const DEBUG:Boolean = false;
		public static const MODE:String = 'infantil';
		// public static const MODE:String = 'adulto';
		
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
		
		private var _bg:Loader;
		
		
		public function Main():void {
			stage.scaleMode = StageScaleMode.NO_SCALE;
			stage.align = StageAlign.TOP_LEFT;
			stage.addEventListener(Event.DEACTIVATE, deactivate);
			if (!Main.DEBUG) stage.displayState = StageDisplayState.FULL_SCREEN_INTERACTIVE;
			stage.addEventListener(Event.RESIZE, onResize);
			
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
			this.addChild(Main.content);
			this.onResize(null);
			
			// background
			this._bg = new Loader();
			if (Main.MODE == 'infantil') {
				this._bg.load(new URLRequest('CreditosInfantil.swf'));
			} else {
				this._bg.load(new URLRequest('CreditosAdulto.swf'));
			}
			Main.content.addChild(this._bg);
			
			// show connection address using qr code
			this._qrCode = new QRCodeDisplay();
			Main.content.addChild(this._qrCode);
			if (Main.MODE == 'infantil') {
				this._qrCode.setCode(this._webServer.serverAddress(this._tcpServer.serverActiveIPv4[0]) + '/abelhas/abelha.html');
				this._qrCode.scaleX = this._qrCode.scaleY = 1.2;
				this._qrCode.x = 80;
				this._qrCode.y = 440;
			} else {
				this._qrCode.setCode(this._webServer.serverAddress(this._tcpServer.serverActiveIPv4[0]) + '/paradoxos/paradoxo.html');
				this._qrCode.scaleX = this._qrCode.scaleY = 1.2;
				this._qrCode.x = 1005;
				this._qrCode.y = 80;
			}
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
					var level:int;
					var thescreen:int;
					var i:uint;
					switch (String(evt.messageData.ac)) {
						case 'bee':
							level = int(Math.round(100 * Number(evt.messageData.height) / Number(evt.messageData.total)));
							if (this._tablets[0].ready) {
								this._tcpServer.sendJSONToClient( { 'ac':'abelha', 'altura': level }, this._tablets[0].socket);
							}
							break;
						case 'setzoom':
							level = int(Math.round(100 * (Number(evt.messageData.pos) - 10) / (Number(evt.messageData.total) - 10)));
							if (level < 0) level = 0;
								else if (level > 100) level = 100;
							thescreen = int(evt.messageData.thescreen);
							if ((thescreen >= 0) && (thescreen <= 3)) {
								if (this._tablets[thescreen].ready) {
									this._tcpServer.sendJSONToClient( { 'ac':'zoom', 'nivel': level }, this._tablets[thescreen].socket);
								}
							} else {
								for (i = 0; i < this.NUMTABLETS; i++) {
									if (this._tablets[i].ready) {
										this._tcpServer.sendJSONToClient( { 'ac':'zoom', 'nivel': level }, this._tablets[i].socket);
									}
								}
							}
							break;
						case 'setside':
							level = int(Math.round(100 * (Number(evt.messageData.pos) - 10) / (Number(evt.messageData.total) - 10)));
							if (level < 0) level = 0;
								else if (level > 100) level = 100;
							thescreen = int(evt.messageData.thescreen);
							if ((thescreen >= 0) && (thescreen <= 3)) {
								if (this._tablets[thescreen].ready) {
									this._tcpServer.sendJSONToClient( { 'ac':'side', 'nivel': level }, this._tablets[thescreen].socket);
								}
							} else {
								for (i = 0; i < this.NUMTABLETS; i++) {
									if (this._tablets[i].ready) {
										this._tcpServer.sendJSONToClient( { 'ac':'side', 'nivel': level }, this._tablets[i].socket);
									}
								}
							}
							break;
						case 'setheight':
							level = int(Math.round(100 * (Number(evt.messageData.pos) - 10) / (Number(evt.messageData.total) - 10)));
							if (level < 0) level = 0;
								else if (level > 100) level = 100;
							thescreen = int(evt.messageData.thescreen);
							if ((thescreen >= 0) && (thescreen <= 3)) {
								if (this._tablets[thescreen].ready) {
									this._tcpServer.sendJSONToClient( { 'ac':'height', 'nivel': level }, this._tablets[thescreen].socket);
								}
							} else {
								for (i = 0; i < this.NUMTABLETS; i++) {
									if (this._tablets[i].ready) {
										this._tcpServer.sendJSONToClient( { 'ac':'height', 'nivel': level }, this._tablets[i].socket);
									}
								}
							}
							break;
						case 'setspeed':
							level = int(Math.round(100 * (Number(evt.messageData.pos) - 10) / (Number(evt.messageData.total) - 10)));
							if (level < 0) level = 0;
								else if (level > 100) level = 100;
							thescreen = int(evt.messageData.thescreen);
							if ((thescreen >= 0) && (thescreen <= 3)) {
								if (this._tablets[thescreen].ready) {
									this._tcpServer.sendJSONToClient( { 'ac':'speed', 'nivel': level }, this._tablets[thescreen].socket);
								}
							} else {
								for (i = 0; i < this.NUMTABLETS; i++) {
									if (this._tablets[i].ready) {
										this._tcpServer.sendJSONToClient( { 'ac':'speed', 'nivel': level }, this._tablets[i].socket);
									}
								}
							}
							break;
						case 'setfont':
							thescreen = int(evt.messageData.thescreen);
							if ((thescreen >= 0) && (thescreen <= 3)) {
								if (this._tablets[thescreen].ready) {
									this._tcpServer.sendJSONToClient( { 'ac':'font' }, this._tablets[thescreen].socket);
								}
							} else {
								for (i = 0; i < this.NUMTABLETS; i++) {
									if (this._tablets[i].ready) {
										this._tcpServer.sendJSONToClient( { 'ac':'font' }, this._tablets[i].socket);
									}
								}
							}
							break;
						case 'setcolor':
							thescreen = int(evt.messageData.thescreen);
							if ((thescreen >= 0) && (thescreen <= 3)) {
								if (this._tablets[thescreen].ready) {
									this._tcpServer.sendJSONToClient( { 'ac':'color' }, this._tablets[thescreen].socket);
								}
							} else {
								for (i = 0; i < this.NUMTABLETS; i++) {
									if (this._tablets[i].ready) {
										this._tcpServer.sendJSONToClient( { 'ac':'color' }, this._tablets[i].socket);
									}
								}
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
				case 'bt1':
					if (this._tablets[0].ready) {
						this._tcpServer.sendJSONToClient( { 'ac':'dentedeleao', 'posicao': 1 }, this._tablets[0].socket);
					}
					break;
				case 'bt2':
					if (this._tablets[0].ready) {
						this._tcpServer.sendJSONToClient( { 'ac':'dentedeleao', 'posicao': 2 }, this._tablets[0].socket);
					}
					break;
				case 'bt3':
					if (this._tablets[0].ready) {
						this._tcpServer.sendJSONToClient( { 'ac':'dentedeleao', 'posicao': 3 }, this._tablets[0].socket);
					}
					break;
				case 'bt4':
					if (this._tablets[1].ready) {
						this._tcpServer.sendJSONToClient( { 'ac':'dentedeleao', 'posicao': 1 }, this._tablets[1].socket);
					}
					break;
				case 'bt5':
					if (this._tablets[1].ready) {
						this._tcpServer.sendJSONToClient( { 'ac':'dentedeleao', 'posicao': 2 }, this._tablets[1].socket);
					}
					break;
				case 'bt6':
					if (this._tablets[1].ready) {
						this._tcpServer.sendJSONToClient( { 'ac':'dentedeleao', 'posicao': 3 }, this._tablets[1].socket);
					}
					break;
				case 'bt7':
					if (this._tablets[2].ready) {
						this._tcpServer.sendJSONToClient( { 'ac':'dentedeleao', 'posicao': 1 }, this._tablets[2].socket);
					}
					break;
				case 'bt8':
					if (this._tablets[2].ready) {
						this._tcpServer.sendJSONToClient( { 'ac':'dentedeleao', 'posicao': 2 }, this._tablets[2].socket);
					}
					break;
				case 'bt9':
					if (this._tablets[2].ready) {
						this._tcpServer.sendJSONToClient( { 'ac':'dentedeleao', 'posicao': 3 }, this._tablets[2].socket);
					}
					break;
				case 'bt10':
					if (this._tablets[3].ready) {
						this._tcpServer.sendJSONToClient( { 'ac':'dentedeleao', 'posicao': 1 }, this._tablets[3].socket);
					}
					break;
				case 'bt11':
					if (this._tablets[3].ready) {
						this._tcpServer.sendJSONToClient( { 'ac':'dentedeleao', 'posicao': 2 }, this._tablets[3].socket);
					}
					break;
				case 'bt12':
					if (this._tablets[3].ready) {
						this._tcpServer.sendJSONToClient( { 'ac':'dentedeleao', 'posicao': 3 }, this._tablets[3].socket);
					}
					break;
			}
		}
		
		private function onResize(evt:Event):void {
			if ((Main.content != null) && (this.stage != null)) {
				Main.content.width = stage.stageWidth;
				Main.content.scaleY = Main.content.scaleX;
				if (Main.content.height > stage.stageHeight) {
					Main.content.height = stage.stageHeight;
					Main.content.scaleX = Main.content.scaleY;
				}
				Main.content.x = (stage.stageWidth - Main.content.width) / 2;
				Main.content.y = (stage.stageHeight - Main.content.height) / 2;
			}
		}
	}
	
}