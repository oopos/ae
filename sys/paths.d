/**
 * OS-specific paths.
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

module ae.sys.paths;

import std.path;

version (Windows)
{
	import std.c.string;
	import std.file;
	import std.exception;

	import win32.shlobj;
	import win32.objidl;
	import win32.windef;
	import win32.winbase;

	string getExecutableName()
	{
		auto path = new char[MAX_PATH];
		path.length = enforce(GetModuleFileNameA(null, path.ptr, path.length));
		return baseName(assumeUnique(path));
	}

	private string getShellPath(int csidl)
	{
		LPITEMIDLIST pidl;
		IMalloc aMalloc;

		auto path = new char[MAX_PATH];
		SHGetSpecialFolderLocation(null, csidl, &pidl);
		if(!SHGetPathFromIDList(pidl, path.ptr))
			path = null;
		path.length = strlen(path.ptr);
		SHGetMalloc(&aMalloc);
		aMalloc.Free(pidl);
		return assumeUnique(path);
	}

	private string getAppDir(string appName, int csidl)
	{
		string dir = getShellPath(csidl) ~ `\` ~ (appName ? appName : getExecutableName());
		if (!exists(dir))
			mkdir(dir);
		return dir;
	}

	string getLocalAppProfile  (string appName = null) { return getAppDir(appName, CSIDL_LOCAL_APPDATA); }
	string getRoamingAppProfile(string appName = null) { return getAppDir(appName, CSIDL_APPDATA); }
}
else // POSIX
{
	import std.string;
	import std.ascii;
	import std.file;

	string getExecutableName()
	{
		// TODO: is this valid with OS X app bundles?
		return baseName(readLink("/proc/self/exe"));
	}

	private string getPosixAppName(string appName)
	{
		string s = appName ? appName : getExecutableName();
		string s2;
		foreach (c; s)
			if (isAlphaNum(c))
				s2 ~= toLower(c);
			else
				if (!s2.endsWith('-'))
					s2 ~= '-';
		return s2;
	}

	string getAppProfile(string appName = null)
	{
		string path = expandTilde("~/." ~ getPosixAppName(appName));
		if (!exists(path))
			mkdir(path);
		return path;
	}

	alias getAppProfile getLocalAppProfile;
	alias getAppProfile getRoamingAppProfile;
}
