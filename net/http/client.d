﻿/* ***** BEGIN LICENSE BLOCK *****
 * Version: MPL 1.1/GPL 3.0
 *
 * The contents of this file are subject to the Mozilla Public License Version
 * 1.1 (the "License"); you may not use this file except in compliance with
 * the License. You may obtain a copy of the License at
 * http://www.mozilla.org/MPL/
 *
 * Software distributed under the License is distributed on an "AS IS" basis,
 * WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License
 * for the specific language governing rights and limitations under the
 * License.
 *
 * The Original Code is the Team15 library.
 *
 * The Initial Developer of the Original Code is
 * Stéphan Kochen <stephan@kochen.nl>
 * Portions created by the Initial Developer are Copyright (C) 2006
 * the Initial Developer. All Rights Reserved.
 *
 * Contributor(s):
 *   Vladimir Panteleev <vladimir@thecybershadow.net>
 *   Vincent Povirk <madewokherd@gmail.com>
 *   Simon Arlott
 *
 * Alternatively, the contents of this file may be used under the terms of the
 * GNU General Public License Version 3 (the "GPL") or later, in which case
 * the provisions of the GPL are applicable instead of those above. If you
 * wish to allow use of your version of this file only under the terms of the
 * GPL, and not to allow others to use your version of this file under the
 * terms of the MPL, indicate your decision by deleting the provisions above
 * and replace them with the notice and other provisions required by the GPL.
 * If you do not delete the provisions above, a recipient may use your version
 * of this file under the terms of either the MPL or the GPL.
 *
 * ***** END LICENSE BLOCK ***** */

/// A simple HTTP client.
module ae.net.http.client;

import std.string;
import std.conv;
import std.datetime;
import std.uri;
import std.utf;

import ae.net.asockets;
import ae.sys.data;
debug import std.stdio;

public import ae.net.http.common;


class HttpClient
{
private:
	ClientSocket conn;
	Data inBuffer;

	HttpRequest currentRequest;

	HttpResponse currentResponse;
	size_t expect;

protected:
	void onConnect(ClientSocket sender)
	{
		string reqMessage = currentRequest.method ~ " ";
		if (currentRequest.proxy !is null) {
			reqMessage ~= "http://" ~ currentRequest.host;
			if (compat || currentRequest.port != 80)
				reqMessage ~= format(":%d", currentRequest.port);
		}
		reqMessage ~= currentRequest.resource ~ " HTTP/1.0\r\n";

		if (!("User-Agent" in currentRequest.headers))
			currentRequest.headers["User-Agent"] = agent;
		if (!compat) {
			if (!("Accept-Encoding" in currentRequest.headers))
				currentRequest.headers["Accept-Encoding"] = "gzip, deflate, *;q=0";
			if (!currentRequest.data.empty)
				currentRequest.headers["Content-Length"] = to!string(currentRequest.data.length);
		} else {
			if (!("Pragma" in currentRequest.headers))
				currentRequest.headers["Pragma"] = "No-Cache";
		}
		foreach (string header, string value; currentRequest.headers)
			reqMessage ~= header ~ ": " ~ value ~ "\r\n";

		reqMessage ~= "\r\n";

		Data data = Data(reqMessage);
		data ~= currentRequest.data;

		//debug (HTTP) writefln("%s", fromWAEncoding(reqMessage));
		conn.send(data.contents);
	}

	void onNewResponse(ClientSocket sender, Data data)
	{
		inBuffer ~= data;

		conn.markNonIdle();

		//debug (HTTP) writefln("%s", fromWAEncoding(cast(string)data));

		auto inBufferStr = cast(string)inBuffer.contents;
		int headersend = inBufferStr.indexOf("\r\n\r\n");
		if (headersend == -1)
			return;

		string[] lines = splitLines(inBufferStr[0 .. headersend]);
		string statusline = lines[0];
		lines = lines[1 .. lines.length];

		int versionend = statusline.indexOf(' ');
		if (versionend == -1)
			return;
		string httpversion = statusline[0 .. versionend];
		statusline = statusline[versionend + 1 .. statusline.length];

		currentResponse = new HttpResponse();

		int statusend = statusline.indexOf(' ');
		if (statusend == -1)
			return;
		currentResponse.status = to!ushort(statusline[0 .. statusend]);
		currentResponse.statusMessage = statusline[statusend + 1 .. statusline.length].idup;

		foreach (string line; lines)
		{
			int valuestart = line.indexOf(": ");
			if (valuestart > 0)
				currentResponse.headers[line[0 .. valuestart].idup] = line[valuestart + 2 .. line.length].idup;
		}

		expect = size_t.max;
		if ("Content-Length" in currentResponse.headers)
			expect = to!uint(strip(currentResponse.headers["Content-Length"]));

		inBuffer = inBuffer[(headersend + 4) * char.sizeof .. inBuffer.length];

		if (expect > inBuffer.length)
			conn.handleReadData = &onContinuation;
		else
		{
			currentResponse.data = inBuffer[0 .. expect];
			conn.disconnect("All data read");
		}
	}

	void onContinuation(ClientSocket sender, Data data)
	{
		inBuffer ~= data;
		sender.markNonIdle();

		if (expect!=size_t.max && inBuffer.length >= expect)
		{
			currentResponse.data = inBuffer[0 .. expect];
			conn.disconnect("All data read");
		}
	}

	void onDisconnect(ClientSocket sender, string reason, DisconnectType type)
	{
		if (type == DisconnectType.Error)
			currentResponse = null;
		else
		if (currentResponse)
			currentResponse.data = inBuffer;

		if (handleResponse)
			handleResponse(currentResponse, reason);

		currentRequest = null;
		currentResponse = null;
		inBuffer.clear;
		expect = -1;
		conn.handleReadData = null;
	}

public:
	string agent = "DHttp/0.1";
	bool compat = false;
	string[] cookies;

public:
	this(TickDuration timeout = TickDuration.from!"seconds"(30))
	{
		assert(timeout.length > 0);
		conn = new ClientSocket();
		conn.setIdleTimeout(timeout);
		conn.handleConnect = &onConnect;
		conn.handleDisconnect = &onDisconnect;
	}

	void request(HttpRequest request)
	{
		//debug writefln("New HTTP request: %s", request.url);
		currentRequest = request;
		currentResponse = null;
		conn.handleReadData = &onNewResponse;
		expect = 0;
		if (request.proxy !is null)
			conn.connect(request.proxyHost, request.proxyPort);
		else
			conn.connect(request.host, request.port);
	}

	bool connected()
	{
		return currentRequest !is null;
	}

public:
	// Provide the following callbacks
	void delegate(HttpResponse response, string disconnectReason) handleResponse;
}

/// Asynchronous HTTP request
void httpGet(string url, void delegate(Data) resultHandler, void delegate(string) errorHandler)
{
	void responseHandler(HttpResponse response, string disconnectReason)
	{
		if (!response)
			errorHandler(disconnectReason);
		else
			try
				resultHandler(response.getContent());
			catch (Exception e)
				errorHandler(e.msg);
	}

	auto client = new HttpClient;
	auto request = new HttpRequest;
	request.resource = url;
	client.handleResponse = &responseHandler;
	client.request(request);
}

/// ditto
void httpGet(string url, void delegate(string) resultHandler, void delegate(string) errorHandler)
{
	httpGet(url,
		(Data data)
		{
			auto result = (cast(string)data.contents).idup;
			std.utf.validate(result);
			resultHandler(result);
		},
		errorHandler);
}
