/**
 * OS-specific configuration storage.
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

module ae.sys.config;

import ae.sys.paths;

version (Windows)
{
	import std.exception;
	import std.utf;
	import std.array;

	import win32.windef;
	import win32.winreg;

	// On Windows, just keep the registry key open and read/write values directly.
	class Config
	{
		this(string appName = null, string companyName = null)
		{
			if (!appName)
				appName = getExecutableName();
			if (companyName)
				appName = companyName ~ `\` ~ appName;

			enforce(RegCreateKeyExW(
				HKEY_CURRENT_USER,
				toUTFz!LPCWSTR(`Software\` ~ appName),
				0,
				null,
				0,
				KEY_READ | KEY_WRITE,
				null,
				&key,
				null) == ERROR_SUCCESS, "RegCreateKeyEx failed");
		}

		~this()
		{
			if (key)
				RegCloseKey(key);
		}

		T read(T)(string name, T defaultValue = T.init)
		{
			try
			{
				static if (is(T : const(char[]))) // strings
				{
					uint bytes = getSize(name);
					enforce(bytes % 2 == 0);
					wchar[] ws = new wchar[bytes / 2];
					readRaw(name, ws);
					enforce(ws[$-1]==0); // should be null-terminated
					return to!T(ws[0..$-1]);
				}
				else
				static if (is(T == long) || is(T == ulong))
				{
					T value;
					readRaw(name, (&value)[0..1]);
					return value;
				}
				else
				static if (is(T : uint) || is(T : bool))
				{
					uint value;
					readRaw(name, (&value)[0..1]);
					return cast(T)value;
				}
				else
					static assert(0, "Can't read values of type " ~ T.stringof);
			}
			catch (Throwable e)
				return defaultValue;
		}

		void write(T)(string name, T value)
		{
			static if (is(T : const(char[]))) // strings
			{
				wstring ws = to!wstring(value ~ '\0');
				writeRaw(name, ws, REG_SZ);
			}
			else
			static if (is(T == long) || is(T == ulong))
				writeRaw(name, (&value)[0..1], REG_QWORD);
			else
			static if (is(T : uint) || is(T : bool))
			{
				uint dwordValue = cast(uint)value;
				writeRaw(name, (&dwordValue)[0..1], REG_DWORD);
			}
			else
				static assert(0, "Can't write values of type " ~ T.stringof);
		}

	private:
		HKEY key;

		void readRaw(string name, void[] dest)
		{
			enforce(getSize(name) == dest.length, "Invalid registry value length for " ~ name);
			DWORD size = dest.length;
			enforce(RegQueryValueExW(key, toUTFz!LPCWSTR(name), null, null, cast(ubyte*)dest.ptr, &size) == ERROR_SUCCESS, "RegQueryValueEx failed");
			enforce(size == dest.length, "Not enough data read");
		}

		void writeRaw(string name, const(void)[] dest, DWORD type)
		{
			enforce(RegSetValueExW(key, toUTFz!LPCWSTR(name), 0, type, cast(ubyte*)dest.ptr, dest.length) == ERROR_SUCCESS, "RegSetValueEx failed");
		}

		uint getSize(string name)
		{
			DWORD size;
			enforce(RegQueryValueExW(key, toUTFz!LPCWSTR(name), null, null, null, &size) == ERROR_SUCCESS);
			return size;
		}
	}
}
else // POSIX
{
	import std.string;
	import std.stdio;
	import std.file;
	import std.path;
	import std.conv;

	// Cache values from memory, and save them to disk when the program exits.
	class Config
	{
		this(string appName = null, string companyName = null)
		{
			fileName = getRoamingAppProfile(appName) ~ "/config";
			if (!exists(fileName))
				return;
			foreach (line; File(fileName, "rt").byLine())
				if (line.length>0 && line[0]!='#')
				{
					int p = line.indexOf('=');
					if (p>0)
						values[line[0..p].idup] = line[p+1..$].idup;
				}
			instances ~= this;
		}

		~this()
		{
			assert(!dirty, "Dirty config destruction");
		}

		T read(T)(string name, T defaultValue = T.init)
		{
			auto pvalue = name in values;
			if (pvalue)
				return to!T(*pvalue);
			else
				return defaultValue;
		}

		void write(T)(string name, T value)
			if (is(typeof(to!string(T.init))))
		{
			values[name] = to!string(value);
			dirty = true;
		}

		void save()
		{
			if (!dirty)
				return;
			auto f = File(fileName, "wt");
			foreach (name, value; values)
				f.writefln("%s=%s", name, value);
			dirty = false;
		}

	private:
		string[string] values;
		string fileName;
		bool dirty;

		static Config[] instances;

		static ~this()
		{
			foreach (instance; instances)
				instance.save();
		}
	}
}
