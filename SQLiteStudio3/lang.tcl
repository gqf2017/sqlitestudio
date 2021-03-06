#!/usr/bin/env tclsh

proc usage {} {
    puts "$::argv0 (add|remove) <lang_name>"
    puts "$::argv0 add_plugin <plugin name>"
    puts "$::argv0 (update|release|status)"
}

lassign $argv op lang

if {$::tcl_platform(platform) == "windows"} {
    set ERR_NULL "2>NUL"
} else {
    set ERR_NULL "2>/dev/null"
}

proc find {dir mask} {
	set results [list]
	foreach f [glob -nocomplain -directory $dir *] {
		if {[file isdirectory $f]} {
			lappend results {*}[find $f $mask]
			continue;
		}
		
		if {[string match $mask [lindex [file split $f] end]]} {
			lappend results $f
		}
	}
	return $results
}

proc countstrings {data search} {
    set l [string length $search]
    set count 0
    while {[set i [string first $search $data]]>=0} {
        incr count
        incr i $l
        set data [string range $data $i end]
    }
    set count
}

proc scanLangs {} {
    set langs [dict create]
    foreach f [find .. "*.ts"] {
        set lang [lindex [regexp -inline {[^_]*_(\w+(\w+)?).ts$} $f] 1]
        if {[dict exists $langs $lang]} {
            set langDict [dict get $langs $lang]
        } else {
            set langDict [dict create translated 0 untranslated 0]
        }
    
        set fd [open $f r]
        set data [read $fd]
        close $fd
        
        set c1 [countstrings $data "<translation>"]
        set c2 [countstrings $data "<translation type=\"unfinished\">"]
        dict incr langDict translated $c1
        dict incr langDict untranslated $c2
        dict set langs $lang $langDict
    }

    return $langs
}

switch -- $op {
    "update" - "release" {
	if {$argc != 1} {
	    usage
	    exit 1
	}

	set files [list]
	foreach p [list coreSQLiteStudio guiSQLiteStudio sqlitestudio sqlitestudiocli] {
	    lappend files $p/$p.pro
	}

	foreach d [glob -directory ../Plugins -tails -nocomplain *] {
	    if {![file isdirectory ../Plugins/$d]} continue
	    lappend files ../Plugins/$d/$d.pro
	}
	
	foreach f $files {
	    catch {
		if {$op == "update"} {
		    exec lupdate $f
		} else {
		    #exec lrelease $f $::ERR_NULL
		    exec lrelease $f
		}
	    } res
	    if {$op == "release"} {
		puts $res
	    } else {
		foreach line [split $res \n] {
		    if {[string first Q_OBJECT $line] > -1} {
			puts $line
		    }
		    if {[regexp -- {^.*\w+\.ts.*$} $line]} {
			puts -nonewline [lindex [regexp -inline -- {^.*"([\w\/\\\.]+\.ts)".*$} $line] 1]
			puts -nonewline ": "
		    }
		    if {[regexp -- {^.*\d+[^\d]+\(\d+[^\d]+\d+.*\).*$} $line]} {
			puts -nonewline [lindex [regexp -inline -- {\S+.*} $line] 0]
			set new [lindex [regexp -inline -- {^.*\d+[^\d]+(\d+)[^\d]+\d+.*$} $line] 1]
			if {$new > 0} {
			    puts -nonewline " <- !!!!!!!!!!!"
			}
			puts ""
		    }
		}
	    }
	}
    }
    "status" {
	set langs [scanLangs]
	foreach k [dict keys $langs] {
	    set lang [dict get $langs $k]
	    set tr [dict get $lang translated]
	    set untr [dict get $lang untranslated]
	    set all [expr {$tr + $untr}]
	    if {$all == 0} continue

	    set perc [expr {round(double($tr)/$all * 1000)/10.0}]
	    
	    set lang [string tolower $lang]
	    puts "$k - ${perc}% ($tr / $all)"
	}
    }
    "add_plugin" {
	if {$argc != 2} {
	    usage
	    exit 1
	}
	
	set plug [lindex $argv 1]
	set plugPro ../Plugins/$plug/$plug.pro
	if {![file exists $plugPro]} {
	    puts "$plugPro does not exist."
	    exit 1
	}
	
	set fd [open ../Plugins/CsvImport/CsvImport.pro r]
	set data [read $fd]
	close $fd
	
	set langs [list]
	set trData "\nTRANSLATIONS += "
	foreach {all lang} [regexp -inline -all -- {CsvImport_(\w+)\.ts} $data] {
	    append trData "\\\n\t\t${plug}_$lang.ts"
	    lappend langs $lang
	}
	append trData "\n"
	
	set fd [open $plugPro a+]
	puts $fd $trData
	close $fd
	puts "Added translation languages for plugin $plug:\n[join $langs \n]"
    }
    "add" - "remove" {
	if {$argc != 2} {
	    usage
	    exit 1
	}

	foreach p [list coreSQLiteStudio guiSQLiteStudio sqlitestudio sqlitestudiocli] {
	    # pro file
	    set fd [open $p/$p.pro r]
	    set data [read $fd]
	    close $fd
	
	    set ts "translations/${p}_$lang.ts"
	    if {$op == "add" && [string first $ts $data] == -1} {
		set data [string map [list "TRANSLATIONS += " "TRANSLATIONS += $ts \\\n\t\t"] $data]
	    } elseif {$op == "remove" && [string first $ts $data] > -1} {
		regsub -- "$ts\\s*(\\\\)?\n\\s*" $data "" data
	    } else {
		continue
	    }
	    
	    set fd [open $p/$p.pro w+]
	    puts $fd $data
	    close $fd
	    
	    puts "Updated $p.pro"
	}

	foreach p [list coreSQLiteStudio guiSQLiteStudio sqlitestudio sqlitestudiocli] {
	    # qrc file
	    set fd [open $p/$p.qrc r]
	    set data [read $fd]
	    close $fd
	
	    set qm "translations/${p}_$lang.qm"
	    if {$op == "add" && [string first $qm $data] == -1} {
		set data [string map [list "<qresource prefix=\"/msg\">" "<qresource prefix=\"/msg\">\n        <file>$qm</file>"] $data]
	    } elseif {$op == "remove" && [string first $qm $data] > -1} {
		regsub -- "\\s*$qm\\s*\n" $data "" data
	    } else {
		continue
	    }

	    set fd [open $p/$p.qrc w+]
	    puts $fd $data
	    close $fd
	    
	    puts "Updated $p.qrc"
	}
	
	foreach d [glob -directory ../Plugins -tails -nocomplain *] {
	    if {![file isdirectory ../Plugins/$d]} continue
	
	    # pro file
	    set fd [open ../Plugins/$d/$d.pro r]
	    set data [read $fd]
	    close $fd

	    if {[string first "TRANSLATIONS +=" $data] == -1} continue

	    set ts "${d}_$lang.ts"
	    if {$op == "add" && [string first $ts $data] == -1} {
		set data [string map [list "TRANSLATIONS += " "TRANSLATIONS += $ts \\\n\t\t"] $data]
	    } elseif {$op == "remove" && [string first $ts $data] > -1} {
		regsub -- "$ts\\s*(\\\\)?\n\\s*" $data "" data
	    } else {
		continue
	    }
	    
	    set fd [open ../Plugins/$d/$d.pro w+]
	    puts $fd $data
	    close $fd
	    
	    puts "Updated $d.pro"
	}
	
	foreach d [glob -directory ../Plugins -tails -nocomplain *] {
	    # qrc file
	    if {![file isdirectory ../Plugins/$d]} continue
	    if {[file exists ../Plugins/$d/$d.qrc]} {
		set fname ../Plugins/$d/$d.qrc
		set fnameOnly $d.qrc
	    } elseif {[file exists ../Plugins/$d/[string tolower $d].qrc]} {
		set fname ../Plugins/$d/[string tolower $d].qrc
		set fnameOnly [string tolower $d].qrc
	    } else {
		continue
	    }
	
	    set fd [open $fname r]
	    set data [read $fd]
	    close $fd

	    if {[string first "<qresource prefix=\"/msg\">" $data] == -1} continue

	    set qm "${d}_$lang.qm"
	    if {$op == "add" && [string first $qm $data] == -1} {
		set data [string map [list "<qresource prefix=\"/msg\">" "<qresource prefix=\"/msg\">\n        <file>$qm</file>"] $data]
	    } elseif {$op == "remove" && [string first $qm $data] > -1} {
		regsub -- "\\s*$qm\\s*\n" $data "" data
	    } else {
		continue
	    }
	    
	    set fd [open $fname w+]
	    puts $fd $data
	    close $fd
	    
	    puts "Updated $fnameOnly"
	}
    }
    default {
        usage
    }
}

