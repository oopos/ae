/**
 * ae.ui.shell.shell
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

module ae.ui.shell.shell;

import ae.ui.video.video;

/// A "shell" handles OS window management, input handling, and various other platform-dependent tasks.
class Shell
{
	abstract void run();

	abstract void setCaption(string caption);

	void quit()
	{
		if (!quitting)
		{
			quitting = true;
			prod();
		}
	}

	/// Wake event thread with a no-op event.
	abstract void prod();

	Video video;

protected:
	bool quitting;
}
