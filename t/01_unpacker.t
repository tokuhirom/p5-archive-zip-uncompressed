use strict;
use warnings;
use Test::More tests => 5;
use Test::Requires 'Archive::Zip';
use Archive::Zip::Uncompressed;
use File::Temp;

my $tmp = File::Temp->new(UNLINK => 0, SUFFIX => '.zip');

{
    my $zip = Archive::Zip::Uncompressed::Packer->new($tmp->filename);
    $zip->add_file('README');
    $zip->add_directory('lib/');
    $zip->add_directory('lib/Archive/');
    $zip->add_directory('lib/Archive/Zip/');
    $zip->add_file('lib/Archive/Zip/Uncompressed.pm');
    $zip->close();
}

{
    my $zip = Archive::Zip->new($tmp->filename);
    {
        my $ofile = File::Temp->new(UNLINK => 1);
        ok( $zip->read( $tmp->filename ) == 0 );
        is($zip->extractMember('README' => $ofile->filename), 0);
        is slurp($ofile->filename), slurp('README');

        my $member = $zip->memberNamed( 'README' );
        ok !$member->isDirectory();
    }
    {
        my $member = $zip->memberNamed( 'lib/' );
        ok $member->isDirectory();
    }
}

exit;

sub slurp {
    my $fname = shift;
    open my $fh, '<', $fname or die $!;
    do { local $/; <$fh> };
}

