set required_vars {STA_OUTDIR STA_SOURCE_FILES STA_TOP_NAME STA_TECHLIB_FILE STA_SDC_FILE STA_CLOCK_PERIOD STA_POWER_TYPE STA_POWER_REPORT_NAME STA_VCD_FILENAME STA_TB_DUT_NAME}
foreach var $required_vars {
    if {![info exists ::env($var)]} {
        puts "Error: Environment variable '$var' is not set."
        exit 1
    }
}

set VERILOG_SRCS      $::env(STA_SOURCE_FILES)
set TOP_NAME          $::env(STA_TOP_NAME)
set LIB_FILE          $::env(STA_TECHLIB_FILE)
set OUTDIR            $::env(STA_OUTDIR)
set SDC_FILE          $::env(STA_SDC_FILE)
set CLOCK_PERIOD      $::env(STA_CLOCK_PERIOD)
set POWER_TYPE        $::env(STA_POWER_TYPE)
set POWER_REPORT_NAME $::env(STA_POWER_REPORT_NAME)
set VCD_FILENAME      $::env(STA_VCD_FILENAME)
set TB_DUT_NAME       $::env(STA_TB_DUT_NAME)

proc read_vcd_and_override_clock_period {scope filename clock_name clock_period} {
    set clock [get_clocks -quiet $clock_name]
    if {$clock eq {}} {
        error "Clock '$clock_name' is not defined in the SDC."
    }
    set sources [get_property $clock sources]
    if {[llength $sources] != 1} {
        error "Clock '$clock_name' must have one source."
    }

    # Temporarily make the clock virtual so its measured VCD activity is visible.
    # Keeping the same clock name preserves constraints that reference it.
    create_clock -name $clock_name -period $clock_period
    read_vcd -scope $scope $filename

    set pins [get_pins -hierarchical *]
    foreach port [get_ports *] {
        lappend pins [sta::get_port_pin $port]
    }
    set activities [dict create]
    foreach pin $pins {
        lassign [get_property $pin activity] density duty origin
        if {$origin eq "vcd"} {
            dict set activities [get_full_name $pin] [list $pin $density $duty]
        }
    }
    create_clock -name $clock_name -period $clock_period $sources
    set source [get_full_name [lindex $sources 0]]
    if {![dict exists $activities $source]} {
        error "VCD has no activity for clock source $source."
    }
    set clock_density [lindex [dict get $activities $source] 1]
    if {$clock_density <= 0.0} {
        error "VCD clock source $source has no transitions."
    }
    set scale [expr {2.0 / ($clock_density * [sta::time_ui_sta $clock_period])}]
    dict for {name activity} $activities {
        lassign $activity pin density duty
        # This native setter uses transitions/second, as does the activity property.
        sta::set_power_pin_activity $pin [expr {$density * $scale}] $duty
    }
    puts "VCD activity normalized to clock $clock_name period $clock_period (density scale $scale)."
}

###############################################################################
#                           OpenSTA Script                                    #
###############################################################################
read_liberty ${LIB_FILE}
foreach file ${VERILOG_SRCS} {
    read_verilog $file
}
link_design ${TOP_NAME}

# SDC constraints
read_sdc ${SDC_FILE}

# reports for power and timing
if {${POWER_TYPE} == 0} {
    set_power_activity -input -activity 0.2
} elseif {${POWER_TYPE} == 1} {
    read_vcd_and_override_clock_period ${TB_DUT_NAME}/dut ${VCD_FILENAME} clk ${CLOCK_PERIOD}
}

report_power -digits 6 > ${OUTDIR}/${POWER_REPORT_NAME}
