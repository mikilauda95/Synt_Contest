proc dualVth {args} {
	parse_proc_arguments -args $args results
		set lvt $results(-lvt)
		set constraint $results(-constraint)

		suppress_message NED-045
		suppress_message PTE-018
		suppress_message PWR-246


		set percent $lvt
		set mode $constraint



#total number of combinational cells
		set tot_cells [comb_cell_number]

#precision of report_bottleneck
		set wpath $tot_cells

#max number of cells to swap in a swap loop
		set mx [expr $tot_cells/10]

#cells swapped to HVT and LVT, with info or only names
		set swapped_cells ""
		set swapped_cells_names ""
		set unswapped_cells ""
		set unswapped_cells_names ""

#loop to swap everything in HVT
		foreach_in_collection curr_cell [get_cells] {
			if { [get_attribute $curr_cell is_combinational] } {
				regsub -all {_LL} [get_attribute $curr_cell ref_name] _LH ccc
					size_cell [get_attribute $curr_cell full_name] "CORE65LPHVT_nom_1.20V_25C.db:CORE65LPHVT/$ccc"
					lappend swapped_cells [ list [get_attribute $curr_cell full_name] $ccc ] 
					lappend swapped_cells_names [ get_attribute $curr_cell full_name]
			}
		}




	set tp  [get_timing_paths]

#set slack pre loop
		set slack [get_attribute $tp slack]

#nsw holds the Number of SWapped cells
		set nsw 0
		set maxcells $mx

		while { $slack <= 0 } {

# if hard and we passed the aximum number of cells, STOP!
			if { $constraint == "hard" && [llength $unswapped_cells_names] >= [expr $lvt*[comb_cell_number]-1]} {
#REMOVE WHEN READY	
				puts "HARD REACHED STOP CONDITION"
					break
			}
#get the value of report_bottleneck and iterate on each line, if it contains a HVT cell, swap it 
			redirect -variable rep {report_bottleneck -max_cells $maxcells -nworst_paths $wpath -cost_type path_cost -through $swapped_cells_names -nosplit}
			set lines [split $rep "\n"]
				set maxswp []
				foreach l $lines {
					set cellname ""
						regexp {(U[0-9]*) *(H\w*)} $l -> cellname refname
						if { $cellname != "" } {
							if { [regsub {_LH} $refname _LL lvtref] == 1 } {

#swap to LVT and fix the lists (remove from swapped and append to swapped	
		size_cell $cellname "CORE65LPLVT_nom_1.20V_25C.db:CORE65LPLVT/$lvtref"
		lappend unswapped_cells_names $cellname
		lappend unswapped_cells [lindex $swapped_cells [lsearch -index 0 $swapped_cells $cellname]]
		mylremove swapped_cells $cellname	
		lremove swapped_cells_names $cellname	

		}
		}

# CHECK IF REACHED MAXIMUM SWAPPABLE CELLS, YES->BREAK
		if { [llength $unswapped_cells_names] >= [expr $lvt*$tot_cells-1] && $constraint == "hard" } { 
		break
		}

		}

#compare previous slack and current slack	
		set prev_slack $slack
		set tp [get_timing_paths]
		set slack [get_attribute $tp slack]
		puts "CURRENT SLACK: $slack "

#increase precision and number of cells if there is no improvement
		if { [llength $swapped_cells] == $nsw || $slack == $prev_slack} { 
			set maxcells [expr $maxcells*2]
				set wpath [expr $wpath*2]

		} else {

			set maxcells $mx
				set wpath $tot_cells
		}
			set nsw [ llength $swapped_cells ]

		}

#HERE first stage is done


	puts "START RECOVERY"
#create the recovery list starting by the unswpped cells list
		set recovery_list ""
		set k 0
		foreach cl $unswapped_cells_names {
			set wp [get_timing_paths -through $cl]
				lappend recovery_list [list $cl [lindex [lindex $unswapped_cells $k] 1] [get_attribute $wp slack]]
				incr k
		}


#sort recovery list by personal slack
#set recovery_list [lsort -real -decreasing -index 2 $recovery_list]

	set k 0
		set nrec 0
		set stop_cond "false"
# try swapping from recovery list, if slack same or better, take it, else swap back
		while {$stop_cond == "false"} {
			size_cell [lindex [lindex $recovery_list $k] 0] "CORE65LPHVT_nom_1.20V_25C.db:CORE65LPHVT/[lindex [lindex $recovery_list $k] 1]"
				set prev_slack $slack
				set slack [get_attribute [get_timing_paths] slack]
				if {  $slack  >=  $prev_slack} {
#better slack, take swap		
					lappend swapped_cells [lindex $recovery_list $k]
						lappend swapped_cells_names [lindex [lindex $recovery_list $k] 0] 
						mylremove unswapped_cells [lindex [lindex $recovery_list $k] 0]
						lremove unswapped_cells_names [lindex [lindex $recovery_list $k] 0]

						set recovery_list [lreplace $recovery_list $k $k]
#		puts "TAKEN SWAP FOR [lindex [lindex $recovery_list $k] 0] : NEW SLACK is $slack"	
						set recovery_list [lreplace $recovery_list $k $k]
						incr nrec
				} else {
#swap back
					regsub -all {_LH} [lindex [lindex $recovery_list $k] 1] _LL ccc
						size_cell [lindex [lindex $recovery_list $k] 0] "CORE65LPLVT_nom_1.20V_25C.db:CORE65LPLVT/$ccc"
						set slack $prev_slack
						incr k
#puts "REJECTED SWAP OF [lindex [lindex $recovery_list $k] 0] : SLACK VIOLATED"
				}

			if { $k > [ expr [llength $recovery_list]-2 ] } { set stop_cond "true" }
		}

	set stop_cond "false"
		set k 0
		puts "NEW RECOVERY"
#same as before, but now simply remain with slack > 0
		while {$stop_cond == "false"} {
			size_cell [lindex [lindex $recovery_list $k] 0] "CORE65LPHVT_nom_1.20V_25C.db:CORE65LPHVT/[lindex [lindex $recovery_list $k] 1]"

				set slack [get_attribute [get_timing_paths] slack]
				if {  $slack  >  0} {
#better slack, take swap		
					lappend swapped_cells [lindex $recovery_list $k]
						lappend swapped_cells_names [lindex [lindex $recovery_list $k] 0]
						mylremove unswapped_cells [lindex [lindex $recovery_list $k] 0]
						lremove unswapped_cells_names [lindex [lindex $recovery_list $k] 0]
#		puts "TAKEN SWAP FOR [lindex [lindex $recovery_list $k] 0] : NEW SLACK is $slack"
						incr nrec
				} else {
#swap back
					regsub -all {_LH} [lindex [lindex $recovery_list $k] 1] _LL ccc
						size_cell [lindex [lindex $recovery_list $k] 0] "CORE65LPLVT_nom_1.20V_25C.db:CORE65LPLVT/$ccc"

#puts "REJECTED SWAP OF [lindex [lindex $recovery_list $k] 0] : SLACK VIOLATED"
				}
			incr k
				if { $k > [ expr [llength $recovery_list]-1 ] } { set stop_cond "true" }
		}

### INSERT YOUR COMMANDS HERE ###
#################################

	return
}

define_proc_attributes dualVth \
			       -info "Post-Synthesis Dual-Vth cell assignment" \
			       -define_args \
{
	{-lvt "maximum % of LVT cells in range [0, 1]" lvt float required}
	{-constraint "optimization effort: soft or hard" constraint one_of_string {required {values {soft hard}}}}
}



proc mylremove {listVariable value} {
	upvar 1 $listVariable var
		set idx [lsearch -index 0 $var $value]
		set var [lreplace $var $idx $idx]
}


proc lremove {listVariable value} {
	upvar 1 $listVariable var
		set idx [lsearch -exact $var $value]
		set var [lreplace $var $idx $idx]
}

proc comb_cell_number {} {
	set k 0
		foreach_in_collection point_cell [get_cells] {
			if { [get_attribute $point_cell is_combinational] } { incr k }
		}
	return $k
}

