function minhaFuncao(oque) {
	alert('recebido: ' + oque);
}

function enviarMMF() {
	return ('do javascript');
}

// websockets
var wsconn;

function wsOnOpen() {

}

function wsOnMessage(evt) {
	var received_msg = evt.data;
}

function wsOnClose() {

}

function wsSend(message) {
	wsconn.send(message);
}
	
function wsSendObject(obj) {
	wsconn.send(JSON.stringify(obj));
}

function openWebSocket() {
	if ("WebSocket" in window) {
		wsconn = new WebSocket(webSocketAddress);
		wsconn.onopen = wsOnOpen;
		wsconn.onmessage = wsOnMessage;
		wsconn.onclose = wsOnClose;
	} else {
		alert("Desculpe, seu navegador não é compatível com nosso controle remoto. Tente apps alternativos como o Mozilla Firefox ou o Google Chrome.");
	}
}

function sendBee(height, total) {
	wsSendObject({ "ac":"bee", "height":height, "total":total });
}

function setZoom(pos, total, thescreen) {
	wsSendObject({ "ac":"setzoom", "pos":pos, "total":total, "thescreen":thescreen });
}

function setSide(pos, total, thescreen) {
	wsSendObject({ "ac":"setside", "pos":pos, "total":total, "thescreen":thescreen });
}

function setHeight(pos, total, thescreen) {
	wsSendObject({ "ac":"setheight", "pos":pos, "total":total, "thescreen":thescreen });
}

function setSpeed(pos, total, thescreen) {
	wsSendObject({ "ac":"setspeed", "pos":pos, "total":total, "thescreen":thescreen });
}

function setFont(thescreen) {
	wsSendObject({ "ac":"setfont", "thescreen":thescreen });
}

function setColor(thescreen) {
	wsSendObject({ "ac":"setcolor", "thescreen":thescreen });
}