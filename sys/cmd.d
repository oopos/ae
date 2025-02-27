/**
 * Simple execution of shell commands, and wrappers for common utilities.
 *
 * License:
 *   This Source Code Form is subject to the terms of
 *   the Mozilla Public License, v. 2.0. If a copy of
 *   the MPL was not distributed with this file, You
 *   can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * Authors:
 *   Vladimir Panteleev <vladimir@thecybershadow.net>
 */

module ae.sys.cmd;

string getTempFileName(string extension)
{
	// TODO: use proper OS directories
	import std.random;
	import std.conv;

	static int counter;
	if (!std.file.exists("data"    )) std.file.mkdir("data");
	if (!std.file.exists("data/tmp")) std.file.mkdir("data/tmp");
	return "data/tmp/run-" ~ to!string(uniform!uint()) ~ "-" ~ to!string(counter++) ~ "." ~ extension;
}

// ************************************************************************

// Quote an argument in a manner conforming to the behavior of CommandLineToArgvW.
// References:
// * http://msdn.microsoft.com/en-us/library/windows/desktop/bb776391(v=vs.85).aspx
// * http://blogs.msdn.com/b/oldnewthing/archive/2010/09/17/10063629.aspx

string escapeWindowsArgument(string arg)
{
	auto escapeIt = new bool[arg.length];
	bool escaping = true;
	foreach_reverse (i, c; arg)
	{
		if (c == '"')
			escapeIt[i] = escaping = true;
		else
		if (c == '\\')
			escapeIt[i] = escaping;
		else
			escaping = false;
	}

	string s = `"`;
	foreach (i, c; arg)
	{
		if (escapeIt[i])
			s ~= '\\';
		s ~= c;
	}
	s ~= '"';

	return s;
}

version(Windows) version(unittest)
{
	import win32.windows;
	import core.stdc.stddef;

	extern (Windows) wchar_t**  CommandLineToArgvW(wchar_t*, int*);
	extern (C) size_t wcslen(in wchar *);

	unittest
	{
		string[] testStrings = [
			`Hello`,
			`Hello, world`,
			`Hello, "world"`,
			`C:\`,
			`C:\dmd`,
			`C:\Program Files\`,
		];

		foreach (c1; `\" _*`)
		foreach (c2; `\" _*`)
		foreach (c3; `\" _*`)
		foreach (c4; `\" _*`)
			testStrings ~= [c1, c2, c3, c4].replace("*", "");

		import std.conv;

		foreach (s; testStrings)
		{
			auto q = escapeWindowsArgument(s);
			LPWSTR lpCommandLine = (to!(wchar[])("Dummy.exe " ~ q) ~ "\0"w).ptr;
			int numArgs;
			LPWSTR* args = CommandLineToArgvW(lpCommandLine, &numArgs);
			scope(exit) LocalFree(args);
			assert(numArgs==2, s ~ " => " ~ q ~ " #" ~ text(numArgs-1));
			auto arg = to!string(args[1][0..wcslen(args[1])]);
			assert(arg == s, s ~ " => " ~ q ~ " => " ~ arg);
		}
	}
}

string escapeShellArgument(string arg)
{
	version (Windows)
	{
		return escapeWindowsArgument(arg);
	}
	else
	{
		// '\'' means: close quoted part of argument, append an escaped
		// single quote, and reopen quotes
		return `'` ~ std.array.replace(arg, `'`, `'\''`) ~ `'`;
	}
}

string escapeShellCommand(string[] args)
{
	import std.array, std.algorithm;
	string command = array(map!escapeShellArgument(args)).join(" ");
	version (Windows)
	{
		// Follow CMD's rules for quote parsing (see "cmd /?").
		command = '"' ~ command ~ '"';
	}
	return command;
}

// ************************************************************************

import std.process;
import std.string;
import std.array;
import std.exception;

string run(string command, string input = null)
{
	string tempfn = getTempFileName("txt"); // HACK
	string tempfn2;
	if (input !is null)
	{
		tempfn2 = getTempFileName("txt");
		std.file.write(tempfn2, input);
		command ~= " < " ~ tempfn2;
	}
	version(Windows)
		system(command ~ ` 2>&1 > ` ~ tempfn);
	else
		system(command ~ ` &> ` ~ tempfn);
	string result = cast(string)std.file.read(tempfn);
	std.file.remove(tempfn);
	if (tempfn2) std.file.remove(tempfn2);
	return result;
}

string run(string[] args)
{
	return run(escapeShellCommand(args));
}

// ************************************************************************

static import std.uri;

string[] extraWgetOptions;
string cookieFile = "data/cookies.txt";

void enableCookies()
{
	if (!std.file.exists(cookieFile))
		std.file.write(cookieFile, "");
	extraWgetOptions ~= ["--load-cookies", cookieFile, "--save-cookies", cookieFile, "--keep-session-cookies"];
}

string download(string url)
{
	auto dataFile = getTempFileName("wget"); scope(exit) if (std.file.exists(dataFile)) std.file.remove(dataFile);
	auto result = spawnvp(P_WAIT, "wget", ["wget", "-q", "--no-check-certificate", "-O", dataFile] ~ extraWgetOptions ~ [url]);
	enforce(result==0, "wget error");
	return cast(string)std.file.read(dataFile);
}

string post(string url, string data)
{
	auto postFile = getTempFileName("txt");
	std.file.write(postFile, data);
	scope(exit) std.file.remove(postFile);

	auto dataFile = getTempFileName("wget"); scope(exit) if (std.file.exists(dataFile)) std.file.remove(dataFile);
	auto result = spawnvp(P_WAIT, "wget", ["wget", "-q", "--no-check-certificate", "-O", dataFile, "--post-file", postFile] ~ extraWgetOptions ~ [url]);
	enforce(result==0, "wget error");
	return cast(string)std.file.read(dataFile);
}

string put(string url, string data)
{
	auto putFile = getTempFileName("txt");
	std.file.write(putFile, data);
	scope(exit) std.file.remove(putFile);

	auto dataFile = getTempFileName("curl"); scope(exit) if (std.file.exists(dataFile)) std.file.remove(dataFile);
	auto result = spawnvp(P_WAIT, "curl", ["curl", "-s", "-k", "-X", "PUT", "-o", dataFile, "-d", "@" ~ putFile, url]);
	enforce(result==0, "curl error");
	return cast(string)std.file.read(dataFile);
}

string shortenURL(string url)
{
	// TODO: proper config support
	if (std.file.exists("data/bitly.txt"))
		return strip(download(format("http://api.bitly.com/v3/shorten?%s&longUrl=%s&format=txt&domain=j.mp", cast(string)std.file.read("data/bitly.txt"), std.uri.encodeComponent(url))));
	else
		return url;
}

string iconv(string data, string inputEncoding, string outputEncoding = "UTF-8")
{
	return run(format("iconv -f %s -t %s", inputEncoding, outputEncoding), data);
}

string sha1sum(void[] data)
{
	auto dataFile = getTempFileName("sha1data");
	std.file.write(dataFile, data);
	scope(exit) std.file.remove(dataFile);

	return run(["sha1sum", "-b", dataFile])[0..40];
}
