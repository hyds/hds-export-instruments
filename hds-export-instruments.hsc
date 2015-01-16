=setup

[Configuration]
ListFileExtension = TXT

[Window]
Name = HDS
Head = Export Instruments Records


[Labels]
FILE     = END   2 10 Export Folder
OUT     = END   +0 +1 Report Output

[Fields] 
FILE     = 3   10 INPUT   CHAR       40  0  FALSE   FALSE  0.0 0.0 'C:\temp\instruments.csv' $OP
OUT     = +0   +1 INPUT   CHAR       10  0  FALSE   FALSE  0.0 0.0 'S' $OP

[Perl]

[Todo]

=cut


=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

  This HYSCRIPT exports instruments for Karl's app
  
=cut

use strict;
use warnings;

use Data::Dumper;
use FileHandle; 
use DateTime;
use Time::localtime;

use Env;
use File::Copy;
use File::stat;
use File::Path qw(make_path remove_tree);
use File::Fetch;
use Try::Tiny;
use Cwd;

use FindBin qw($Bin);

## Kisters modules
use HyTSFile;
use HydDllp;

## Kisters libraries
require 'hydlib.pl';

## HDS Modules
#use local::lib "$Bin/HDS/";
use local::lib "C:/Hydstra/hyd/dat/ini/HDS/";

## Globals
my $prt_fail = '-P';


main: {
  
  my ($dll,$use_hydbutil,%ini,%temp,%errors);
  
  #Get config values
  my $inipath       = HyconfigValue('INIPATH');
  my $temp          = HyconfigValue('TEMPPATH');
  my $junk          = HyconfigValue('JUNKPATH');
  
  my $workarea = 'priv.histupd';
  my $hdspath = $inipath.'HDS\\';
  MkDir($junk);
  
  #Import config
  my $script     = lc(FileName($0));
  IniHash($ARGV[0],\%ini, 0, 0);
  #IniHash($hdspath.$script.'.ini',\%ini, 0 ,0);
  
  #Gather parameters
  #my $export_dir     = $ini{perl_parameters}{dir};  
  my $export_file     = $ini{perl_parameters}{file};
  my $reportfile     = $ini{perl_parameters}{out};  
  
  #Gather export fields
  my @export_fields = ('make','model','serial','station','variable','varnam','descr','recaldue','region');
  
  open my $export, ">", $export_file;
  my $header = join(',',@export_fields );
  print $export "$header\n";
  close ($export);
  
  #Set datetimes
  my $dt = DateTime->now(time_zone => 'local');
  
  
  $dll = HydDllp->New();
  
  print "fetching variable table\n";
  my $varref = $dll->JSonCall( {
    'function' => 'get_db_info',
    'version'  => 3,
    'params'   => {
      'table_name'  => 'variable',
      'return_type' => 'hash',
    }
  }, 1000000);
  my %var = %{$varref->{return}->{rows}};
 
  my @inst_fields = ('make','model','serial','station','variable');
  
  print "fetching instreg\n";
  my $instregref = $dll->JSonCall( {
    'function' => 'get_db_info',
    'version'  => 3,
    'params'   => {
      'table_name'  => 'instreg',
      'field_list'  => \@inst_fields,
      'return_type' => 'array',
      'complex_filter'  => [
        {
          'combine'   => 'OR',
          'left'      => '(', #begin OR
          'fieldname' => 'station',
          'operator'  => 'NE',
          'value'     => 'WRITEOFF',
        },
        {
          'fieldname' => 'station',
          'operator'  => 'NE',
          'value'     => 'WRITEOFF_DSEMOD',
          'right'     => ')', #end OR
        },
        {
          'combine'   => 'AND',
          'left'      => '(', #begin AND
          'fieldname' => 'make',
          'operator'  => 'EQ',
          'value'     => 'ES&S',
          'right'     => ')', #end AND
        }
      ]
    }
  }, 1000000);
  my @instreg = @{$instregref->{return}->{rows}};
  
  my $row_count = 0;
  foreach my $reg (@instreg){
    my $nowdat = $dt->ymd(''); 
    my $nowtim = $dt->hms('');
    $nowtim = substr ($nowtim,0,4); 
    print "[$nowtim]";
    
    $row_count ++;
    my $make      = $reg->{make};
    my $model     = $reg->{model};
    my $serial    = $reg->{serial};
    my $variable  = $reg->{variable};
    my $station   = $reg->{station};
    
    $$reg{varnam} = (  ! defined ($var{$variable}{descr}) || $variable == 0)? "undefined" : $var{$variable}{varnam};
    
    print " processing instreg row [$row_count/$#instreg] : $make, $model, $serial\n";
    print "  getting instcal\r";
    my $instcalref = $dll->JSonCall( {
      'function' => 'get_db_info',
      'version'  => 3,
      'params'   => {
        'table_name'  => 'instcal',
        'field_list'  => ['recaldue'],
        'return_type' => 'array',
        'complex_filter'  => [
          {
            'combine'   => 'AND',
            'left'      => '(', #begin OR
            'fieldname' => 'make',
            'operator'  => 'EQ',
            'value'     => $make,
          },
          {
            'fieldname' => 'model',
            'operator'  => 'EQ',
            'value'     => $model,
          },
          {
            'fieldname' => 'serial',
            'operator'  => 'EQ',
            'value'     => $serial,
            'right'     => ')', #end AND
          }
        ]
      }
    }, 10000);
    
    my @cals = @{$instcalref->{return}->{rows}};
    my $recaldue = $cals[$#cals]->{recaldue};
    $$reg{recaldue} = $recaldue;
    
    print "  getting instmod\r";
    my $instmodref = $dll->JSonCall( {
      'function' => 'get_db_info',
      'version'  => 3,
      'params'   => {
        'table_name'  => 'instmod',
        'field_list'  => ['descr'],
        'return_type' => 'array',
        'complex_filter'  => [
          {
            'combine'   => 'AND',
            'left'      => '(', #begin OR
            'fieldname' => 'make',
            'operator'  => 'EQ',
            'value'     => $make,
          },
          {
            'fieldname' => 'model',
            'operator'  => 'EQ',
            'value'     => $model,
            'right'     => ')', #end AND
          }
        ]
      }
    }, 10000);
    $$reg{descr} = $instmodref->{return}->{rows}->[0]->{descr};
    
    print "  getting site\n";
    my $siteref = $dll->JSonCall( {
      'function' => 'get_db_info',
      'version'  => 3,
      'params'   => {
        'table_name'  => 'site',
        'field_list'  => ['region'],
        'return_type' => 'array',
        'sitelist_filter'   => $station
      }
    }, 1000000);  
    
    $$reg{region} = $siteref->{return}->{rows}->[0]->{region};
    
    my $row_string = '';
    my %data = %{$reg};
    
    
    open my $export, ">>", $export_file;
    
    print "  printing row to report\n";
    foreach my $field (@export_fields){
      $row_string .= "$data{$field},"; 
    }
    $row_string =~ s{,$}{};
    print $export "$row_string\n";
    
    close ($export);

  }
}

1; # End of exporter