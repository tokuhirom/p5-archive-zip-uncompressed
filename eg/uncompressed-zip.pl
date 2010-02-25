use strict;
use warnings;
use Archive::Zip::Uncompressed;

my $ofname = shift @ARGV or die "Usage: $0 foo.zip files";
my $zip = Archive::Zip::Uncompressed::Packer->new($ofname);
for my $file (@ARGV) {
    if (-d $file) {
        $file =~ s{([^/])$}{$1/};
        $zip->add_directory($file);
    } else {
        $zip->add_file($file);
    }
}

