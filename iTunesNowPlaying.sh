#!/bin/sh
#
# OSX shell script to get current itunes track information and write to a file for OBS. 
# Thanks to http://hints.macworld.com/article.php?story=20011108211802830 
# This relies on osascript so likely isn't useful on systems other than OSX.  
#
# Edit "outputDir" to say where your OBS browser source files will go.
# (not the same as the script directory). This works across a network share as long
#   as the remote directory is already mounted, which is how I use it.  
#
# Needs a file called "noart.jpg" to use when no album art is present.
# will copy the file "nowplaying.css" to the target directory to use as a stylesheet.
# 
# Customize your colours and styles in the nowplaying.css. Edit the local nowplaying.css 
#   as the remote one will get overwritten.  
# Tries to write a file only when the track changes to cut down on file writing traffic. 
# HTML uses a meta refresh to reload itself as the file changes in the background.
#
# To use in OBS, use a Browser Source pointing to the local file "nowplaying.htm"
# by default I make it work with an 800x130 browser source box.
#
# Use ctrl-c to stop the script, and have it clean up the browser source on exit. 
#
# November 2020 - April 2021


# Clean up in the event we ctrl-c out of the program, clear the file so old 
# info isn't on screen
function trap_ctrlc()
{
	echo "\nctrl-c, cleaning up file"
	if [ -f "$outputDir/$outputFile" ]; then
		echo "<head><meta http-equiv=\"refresh\" content=\"2\"></head>" > $outputDir/$outputFile
		echo "Done"
	fi
	exit 
}

# this sets up the ctrl-c trap
trap "trap_ctrlc" 2

# Output directory and file.  This can be a network share as long as it's mounted in OSX. 
outputDir="/Volumes/Users/Steven Cogswell/Desktop";
outputFile="nowplaying.htm";

# Use this variable as a watchdog to see if the track has changed since the last iteration
lastOutput=""; 

# loop forever until you ctrl-c the program
while :
do

# Get the full path to the directory the script is in, surprisingly complicated on OSX
# https://serverfault.com/questions/40144/how-can-i-retrieve-the-absolute-filename-in-a-shell-script-on-mac-os-x
currentDir="$(cd "$(dirname "$0")" && pwd -P)"

# Check if the output directory exists
if [ ! -d "$outputDir" ]; then
	echo "Output directory not found ($outputDir)";
	exit;
fi

# Copy the html file to the output directory, if it doesn't previously exist give
# a warning you might have to hit "refresh" in OBS.  
if [ ! -f "$outputDir/$outputFile" ]; then
	echo "Trying to generate html file, check for it ($outputFile in $outputDir)";
	echo "<head><meta http-equiv=\"refresh\" content=\"2\"></head>\n" > $outputDir/$outputFile;
	# The file should now exist, but let's make sure.  
	if [ -f "$outputDir/$outputFile" ]; then
		echo "success. You may have to refresh the browser source in OBS.";
	else
		"Still can't find the file. check for it ($outputDir/$outputFile)";
		exit;
	fi
fi

state=`osascript -e 'tell application "iTunes" to player state as string'`;
printf "\r\033[0KiTunes is currently [$state]";  # uses weird control sequence to overprint the current line
if [ $state = "playing" ]; then
	artist=`osascript -e 'tell application "iTunes" to artist of current track as string'`;
	track=`osascript -e 'tell application "iTunes" to name of current track as string'`;
	album=`osascript -e 'tell application "iTunes" to album of current track as string'`;
	thisOutput="$artist$track$album"  # Track changes in tracks 
	
	if [ ! "$thisOutput" = "$lastOutput" ]; then
		printf "\nTRACK CHANGE\n";   
		printf "$track by $artist ($album)\n"; 
		lastOutput=$thisOutput;  
		
		# clean up previous album art
		if [ -f "$currentDir/albumart.jpg" ]; then
			rm "$currentDir/albumart.jpg"
		fi

		if [ -f "$currentDir/albumart.png" ]; then
			rm "$currentDir/albumart.png"
		fi
		 
		# Run osascript with a heredoc so we don't have to put the script in a separate file.
		# Note this script works with POSIX paths so we can use local script variables
		osascript <<EOD
-- adapted from https://stackoverflow.com/questions/16995273/getting-artwork-from-current-track-in-applescript
-- get the raw bytes of the artwork into a var
try 
tell application "iTunes" to tell artwork 1 of current track
    set srcBytes to raw data
    -- figure out the proper file extension
    if format is «class PNG » then
        set ext to ".png"
    else
        set ext to ".jpg"
    end if
end tell
on error the errorMessage number the errorNumber
	return
end try 

-- get the filename, using POSIX paths since we're working inside a sh script
set thisDirectory to "$currentDir"
set filePath to ((Posix path of thisDirectory) & "/")
set fileName to ( filePath & "albumart" & ext)
-- write to file
set outFile to open for access POSIX file fileName with write permission
-- truncate the file
set eof outFile to 0
-- write the image bytes to the file
write srcBytes to outFile
close access outFile	
EOD
		# If the album art came out as png, let's convert it to jpeg. 
		if [ -f "$currentDir/albumart.png" ]; then
			SIPS=`sips -s format jpeg albumart.png --out albumart.jpg`;
			rm "$currentDir/albumart.png";
		fi
	
		if [ ! -f "$currentDir/albumart.jpg" ]; then    # Failsafe in case no album art file shows up
			echo "Can't find $currentDir/albumart.jpg using $currentDir/noart.jpg"; 
			cp "$currentDir/noart.jpg" "$outputDir/albumart.jpg";
		else 
			cp "$currentDir/albumart.jpg" "$outputDir";
		fi
		
		if [ ! -f "$currentDir/nowplaying.css" ]; then  # Check for stylesheet in this directory
			echo "Can't find style sheet ""$currentDir/nowplaying.css";
		else
			cp "$currentDir/nowplaying.css" "$outputDir"; 
		fi
		
		# Write a little browser-source html file with the information in it.  Uses nowplaying.css in the same folder
		# as where you write the file. 
		echo "<head><meta http-equiv=\"refresh\" content="2"><link rel=\"stylesheet\" href=\"nowplaying.css\"></head>
	      	<table>
	      	<td><img src=\"albumart.jpg\" width=\"128\"></td>
	      	<td>
	      	<div class=\"infobox\">
	      	<div class=\"track\">\"$track\"</div>
		  	<div class=\"artist\">$artist</div>
		  	<div class=\"album\">$album</div>
		  	</div>
		  	</td>" > $outputDir/$outputFile;
		#echo "wrote new track details"
	fi
else
	# Nothing is playing, blank output
	lastOutput=""; 
	echo "<head><meta http-equiv=\"refresh\" content=\"2\"></head>" > $outputDir/$outputFile;
fi

# Wait to check again
sleep 2

done   # While wait forever 
