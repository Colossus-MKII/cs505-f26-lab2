set required_vars {STA_OUTDIR STA_SOURCE_FILES STA_TOP_NAME STA_TECHLIB_FILE STA_SDC_FILE STA_CLOCK_PERIOD STA_TIMING_REPORT_NAME}
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
set REPORT_NAME       $::env(STA_TIMING_REPORT_NAME)

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

# reports for timing
report_checks -digits 8 -endpoint_path_count 1000 -group_path_count 1000 > ${OUTDIR}/timing-longest-paths.rpt

with_output_to_variable max_slack_string {report_worst_slack -digits 8 -max}
set max_slack [string map {"-" ""} [lindex [split $max_slack_string " "] 3]]

set file_id [open "${OUTDIR}/${REPORT_NAME}" w]
puts -nonewline $file_id $max_slack
close $file_id

with_output_to_variable units {report_units}
set file_id [open "${OUTDIR}/units.log" w]
puts -nonewline $file_id $units
close $file_id
