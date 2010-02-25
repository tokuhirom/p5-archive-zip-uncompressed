use strict;
use warnings;
use Test::More tests => 7;
use Test::Requires 'Archive::Zip';
use Archive::Zip::Uncompressed;
use File::Temp;

my $tmp = File::Temp->new(UNLINK => 0, SUFFIX => '.zip');

# create zip file by Archive::Zip
{
    my $zip = Archive::Zip->new();
    my $member_f = $zip->addFile('README');
    $member_f->desiredCompressionMethod(Archive::Zip::COMPRESSION_STORED);
    my $member_d = $zip->addDirectory('lib');
    is $zip->writeToFileNamed($tmp->filename), 0;
}

# get content by Archive::Zip::Uncompressed
{
    my $zip = Archive::Zip::Uncompressed::Unpacker->new($tmp->filename);

    do {
        my $file = $zip->next();
        is $file->filename, 'README';
        is $file->read(my $buf, 1024), -s 'README';
        is $buf, slurp('README');
    };

    do {
        my $file = $zip->next();
        is $file->filename, 'lib/';
        is $file->read(my $buf, 1024), 0;
        is $buf, '';
    };
}

sub slurp {
    my $fname = shift;
    open my $fh, '<', $fname or die $!;
    do { local $/; <$fh> };
}

