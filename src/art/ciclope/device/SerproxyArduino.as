package art.ciclope.device {
	
	// FLASH PACKAGES
	import flash.desktop.NativeProcess;
	import flash.desktop.NativeProcessStartupInfo;
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.events.IEventDispatcher;
	import flash.events.ProgressEvent;
	import flash.events.IOErrorEvent;
	import flash.events.NativeProcessExitEvent;
	import flash.filesystem.File;
	import flash.filesystem.FileMode;
	import flash.filesystem.FileStream;
	import flash.net.Socket;
	import flash.desktop.NativeApplication;
	import flash.utils.setInterval;
	import flash.utils.clearInterval;
	import flash.utils.setTimeout;
	
	/**
	 * SerproxyArduino provides methods to interact with the Serproxy GPL application to communicate with connected Arduino boards.
	 * This class requires the following files to be put at the root level of the AIR package:
	 * 1. serproxy.exe, a GPL proxy to communicate with the connected Arduinos, found at http://www.lspace.nildram.co.uk/freeware.html
	 * 2. gpl-3.0.txt, the GPL license that must be distributed along with serproxy
	 * 3. a bat file named killserproxy.bat with this content: "taskkill /F /IM serproxy.exe"
	 * SerproxyArduino is distributed under the LGPL v3 license found at https://www.gnu.org/licenses/lgpl-3.0.txt . This means you can use it freely on your own projects - they don't need to be licensed under LGPL, but any changes made to this class itself MUST be released under LGPL.
	 * @author Lucas Junqueira <lucas@ciclope.art.br>
	 */
	public class SerproxyArduino extends EventDispatcher {
		
		// PUBLIC VARIABLES
		
		/**
		 * Try to restart the Serproxy process if it exits?
		 */
		public var restartOnExit:Boolean = false;
		
		/**
		 * Windows command prompt (cmd.exe) native path.
		 */
		public var cmdPath:String = 'C:\\WINDOWS\\System32\\cmd.exe';
		
		/**
		 * Time, in seconds, to put Serproxy process to sleep.
		 */
		public var spTimeout:uint = 86400;
		
		/**
		 * Try to keep Serproxy connection alive by sending an emputy string to all connected COM ports every minute?
		 */
		public var tryKeepAlive:Boolean = true;
		
		// PRIVATE VARIABLES
		
		private var _socket:Vector.<Socket>;				// the communication sockets
		private var _received:Vector.<String>;				// data received from connected Arduinos
		private var _process:NativeProcess;					// native process connection for serproxy.exe
		private var _serproxy:File;							// serproxy.exe file reference
		private var _bauds:Vector.<uint>					// Arduino serial baud rates for each port
		private var _coms:Vector.<uint>;					// com ports to use
		private var _ports:Vector.<uint>;					// tcp ports for communication
		private var _running:Boolean;						// is serproxy running?
		private var _nextPort:uint;							// next automatic tcp port to assign
		private var _interval:int;							// interval to keep connection alive
		private var _cmd:NativeProcess;						// kill serproxy process
		
		/**
		 * SerproxyArduino constructor.
		 * @param	autotcpstart	initial tcp port number for automatic tcp ports assign
		 */
		public function SerproxyArduino(autotcpstart:uint = 5000) {
			// prepare event dispatcher
			super(null);
			// prepare Serproxy executable on application storage area
			this._serproxy = File.applicationDirectory.resolvePath('serproxy.exe');
			// prepare connection
			this._bauds = new Vector.<uint>();
			this._coms = new Vector.<uint>();
			this._ports = new Vector.<uint>();
			this._nextPort = autotcpstart;
			this._running = false;
			this._socket = new Vector.<Socket>();
			this._received = new Vector.<String>();
			this._interval = -1;
			// force serproxy process close on exit
			NativeApplication.nativeApplication.addEventListener(Event.EXITING, onApplicationExit);
		}
		
		// READ-ONLY VALUES
		
		/**
		 * Is the Serproxy process running?
		 */
		public function get running():Boolean {
			return (this._running);
		}
		
		// PUBLIC METHODS
		
		/**
		 * Add an Arduino serial connection.
		 * @param	com	the connection com port
		 * @param	tcpport	the tcp port to listen to (lower than 1024 for automatic set)
		 * @param	baud	the connection baud rate
		 * @return	true if the Arduino is add, false if serproxy is already running and the new Arduino com was not add
		 */
		public function addArduino(com:uint, tcpport:int = 0, baud:uint = 9600):Boolean {
			// if serproxy is already running, no Arduino can be add
			if (this._running) {
				return (false);
			} else {
				// automatic set of tcp port?
				if (tcpport < 1024) {
					this._nextPort++;
					tcpport = this._nextPort;
				}
				// is this com port already set?
				var i:uint;
				var found:int = -1;
				for (i = 0; i < this._coms.length; i++) {
					if (this._coms[i] == com) found = i;
				}
				// add new arduino serial or update existing one?
				if (found < 0) {
					this._coms.push(com);
					this._ports.push(tcpport);
					this._bauds.push(baud);
				} else {
					this._coms[found] = com;
					this._ports[found] = tcpport;
					this._bauds[found] = baud;
				}
				return (true);
			}
		}
		
		/**
		 * Remove an Arduino serial connection.
		 * @param	com	the com port to remove
		 * @return	true if the com connection is found and removed, false if serproxy is already running or the com port was not found
		 */
		public function removeArduino(com:uint):Boolean {
			// if serproxy is already running, no Arduino can be removed
			if (this._running) {
				return (false);
			} else {
				var found:int = -1;
				for (var i:uint = 0; i < this._coms.length; i++) {
					if (com == this._coms[i]) found = i;
				}
				// com port found?
				if (found < 0) {
					return (false); // no com port found to be removed
				} else {
					this._coms.splice(found, 1);
					this._ports.splice(found, 1);
					this._bauds.splice(found, 1);
					return (true);
				}
			}
		}
		
		/**
		 * Send a message to a connected Arduino board.
		 * @param	com	the com port of the connected Arduino
		 * @param	message	the message to send
		 * @return	true if the message was sent, false if the serproxy process is not running or the com port was not found
		 */
		public function sendToArduino(com:uint, message:String):Boolean {
			if (this._running) {
				var found:int = -1;
				for (var i:uint = 0; i < this._coms.length; i++) {
					if (this._coms[i] == com) found = i;
				}
				if (found < 0) {
					// com port not found
					return (false);
				} else {
					var socket:Socket;
					if (this._socket[found] == null) {
						try {
							socket = new Socket('127.0.0.1', this._ports[found]);
							socket.addEventListener(ProgressEvent.SOCKET_DATA, onSocketData);
						} catch (e:Error) { }
					} else if (!this._socket[found].connected) {
						try { this._socket[found].removeEventListener(ProgressEvent.SOCKET_DATA, onSocketData); } catch (e:Error) { }
						socket = new Socket('127.0.0.1', this._ports[found]);
						socket.addEventListener(ProgressEvent.SOCKET_DATA, onSocketData);
						this._socket[found] = socket;
					}
					// send data to the connected Arduino
					if (this._socket[found].connected) {
						this._socket[found].writeUTFBytes(message);
						this._socket[found].flush();
						return (true);
					} else {
						return (false);
					}
				}
			} else {
				// serproxy process not running
				return (false);
			}
		}
		
		/**
		 * Start the Serproxy process and begin Arduino connection.
		 * @return true if the process was correctly started, false if it was already running or no Arduino com was set
		 */
		public function start():Boolean {
			if (this._running) {
				return (false); // serproxy was already running
			} else if (this._coms.length == 0) {
				return (false); // no Arduinos set yet
			} else {
				// kill any previous serxproxy process and continue start after that
				this.killSerproxy(true);
				return (true);
			}
		}
		
		/**
		 * Stop the Serproxy process.
		 * @return	true if the process was running and stopped, false if it was not running
		 */
		public function stop():Boolean {
			if (this._running) {
				// exit process
				this._process.exit(true);
				this._running = false;
				// removing any tcp sockets
				while (this._socket.length > 0) {
					try { this._socket[0].removeEventListener(ProgressEvent.SOCKET_DATA, onSocketData); } catch (e:Error) { }
					try { this._socket[0].close(); } catch (e:Error) { }
					this._socket.shift();
					this._received.shift();
				}
				try { clearInterval(this._interval); } catch (e:Error) { }
				return (true);
			} else {
				// serproxy process not running
				return (false);
			}
		}
		
		/**
		 * Kill the Serproxy process.
		 */
		public function killSerproxy(startAfter:Boolean = false):void {
			// prepare cmd process setup
			var nativeProcessStartupInfo:NativeProcessStartupInfo = new NativeProcessStartupInfo();
			var args:Vector.<String> = new Vector.<String>();
			args.push('/c', File.applicationDirectory.resolvePath('killserproxy.bat').nativePath);
			nativeProcessStartupInfo.executable = new File(this.cmdPath);
			nativeProcessStartupInfo.arguments = args;
			// start process
			this._cmd = new NativeProcess();
			this._cmd.start(nativeProcessStartupInfo);
			if (startAfter) {
				setTimeout(afterKillStart, 250);
			} else {
				setTimeout(afterKill, 250);
			}
		}
		
		// PRIVATE METHODS
		
		/**
		 * Continue Serproxy startup.
		 */
		private function continueStart():void {
			// prepare config file contents
			var cnf:String = "# SerproxyArduino dynamic config file\r\n";
			cnf += "# default settings\r\n";
			cnf += "comm_baud=9600\r\n";
			cnf += "comm_databits=8\r\n";
			cnf += "comm_stopbits=1\r\n";
			cnf += "comm_parity=none\r\n";
			cnf += "timeout=" + this.spTimeout + "\r\n";
			cnf += "# comm ports used\r\n";
			cnf += "comm_ports=" + this._coms.join(',') + "\r\n";
			for (var icom:uint = 0; icom < this._coms.length; icom++) {
				cnf += "# port " + this._coms[icom] + " settings\r\n";
				cnf += "net_port" + this._coms[icom] + "=" + this._ports[icom] + "\r\n";
				cnf += "comm_baud" + this._coms[icom] + "=" + this._bauds[icom] + "\r\n";
			}
			// create file
			var config:File = File.applicationStorageDirectory.resolvePath('serproxy.cfg');
			if (config.exists) config.deleteFile();
			var stream:FileStream = new FileStream();
			stream.open(config, FileMode.WRITE);
			stream.writeUTFBytes(cnf);
			stream.close();
			// prepare startup information
			var nativeProcessStartupInfo:NativeProcessStartupInfo = new NativeProcessStartupInfo();
			var args:Vector.<String> = new Vector.<String>();
			nativeProcessStartupInfo.executable = this._serproxy;
			nativeProcessStartupInfo.workingDirectory = File.applicationStorageDirectory; 
			nativeProcessStartupInfo.arguments = args;
			// start process
			this._process = new NativeProcess();
			this._process.addEventListener(ProgressEvent.STANDARD_OUTPUT_DATA, onOutputData);
			this._process.addEventListener(ProgressEvent.STANDARD_ERROR_DATA, onErrorData);
			this._process.addEventListener(NativeProcessExitEvent.EXIT, onProcessExit);
			this._process.addEventListener(IOErrorEvent.STANDARD_OUTPUT_IO_ERROR, onIOError);
			this._process.addEventListener(IOErrorEvent.STANDARD_ERROR_IO_ERROR, onIOError);
			this._process.start(nativeProcessStartupInfo);
			this._running = true;
			// prepare communication sockets
			while (this._socket.length > 0) { // removing any previous sockets
				try { this._socket[0].removeEventListener(ProgressEvent.SOCKET_DATA, onSocketData); } catch (e:Error) { }
				try { this._socket[0].close(); } catch (e:Error) { }
				this._socket.shift();
				this._received.shift();
			}
			for (icom = 0; icom < this._coms.length; icom++) {
				try {
					var socket:Socket = new Socket('127.0.0.1', this._ports[icom]);
					socket.addEventListener(ProgressEvent.SOCKET_DATA, onSocketData);
				} catch (e:Error) { }
				this._socket.push(socket);
				this._received.push('');
			}
			// keep connection alive
			this._interval = setInterval(keepAlive, 60000);
		}
		
		/**
		 * Exit Serproxy close process.
		 */
		private function afterKill():void {
			this._cmd.exit();
		}
		
		/**
		 * Exit Serproxy close process and continue startup.
		 */
		private function afterKillStart():void {
			this._cmd.exit();
			this.continueStart();
		}
		
		/**
		 * Output data received from native process.
		 */
		private function onOutputData(event:ProgressEvent):void {
			this.dispatchEvent(new SerproxyArduinoEvent(SerproxyArduinoEvent.OUTPUT, this._process.standardOutput.readUTFBytes(this._process.standardOutput.bytesAvailable)));
        }
        
		/**
		 * Error data received from native process.
		 */
        private function onErrorData(event:ProgressEvent):void {
			this.dispatchEvent(new SerproxyArduinoEvent(SerproxyArduinoEvent.ERROR, this._process.standardError.readUTFBytes(this._process.standardError.bytesAvailable)));
        }
        
		/**
		 * Native process exit.
		 */
        private function onProcessExit(event:NativeProcessExitEvent):void {
			this.stop();
			this.dispatchEvent(new SerproxyArduinoEvent(SerproxyArduinoEvent.EXIT, String(event.exitCode)));
			if (this.restartOnExit) this.start();
        }
        
		/**
		 * IO error found on native process execution.
		 */
        private function onIOError(event:IOErrorEvent):void {
			this.dispatchEvent(new SerproxyArduinoEvent(SerproxyArduinoEvent.EXIT, event.toString()));
        }
		
		/**
		 * Information received from a connected Arduino.
		 */
		private function onSocketData(event:ProgressEvent):void {
			// check the sending Arduino
			var arduino:int = -1;
			for (var i:uint = 0; i < this._socket.length; i++) {
				if (event.target == this._socket[i]) arduino = i;
			}
			if (arduino >= 0) {
				this._received[arduino] += this._socket[arduino].readUTFBytes(this._socket[arduino].bytesAvailable);
				var rcvData:Array = this._received[arduino].split("\r\n");
				if (this._received[arduino].substr( -1, "\r\n".length) != "\r\n") {
					this._received[arduino] = String(rcvData.pop());
				} else {
					this._received[arduino] = '';
				}
				while (rcvData.length > 0) {
					// send prepared received message with com port origin
					this.dispatchEvent(new SerproxyArduinoEvent(SerproxyArduinoEvent.DATARECEIVED, String(rcvData.pop()), this._coms[arduino]));
				}
			} else {
				// send raw received message without com port id
				this.dispatchEvent(new SerproxyArduinoEvent(SerproxyArduinoEvent.DATARECEIVED, String(rcvData.pop())));
			}
		}
		
		/**
		 * Force Serproxy process to exit on application quit.
		 */
		private function onApplicationExit(evt:Event):void {
			this.killSerproxy();
		}
		
		/**
		 * Keep the connection to the Serproxy process alive.
		 */
		private function keepAlive():void {
			if (this._running && this.tryKeepAlive) {
				for (var i:uint = 0; i < this._coms.length; i++) {
					this.sendToArduino(this._coms[i], '');
				}
			}
		}
		
	}

}