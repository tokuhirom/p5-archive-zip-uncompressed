package Archive::Zip::Uncompressed;
use strict;
use warnings;
use 5.00800;
use Archive::Zip::Uncompressed::Unpacker;
use Archive::Zip::Uncompressed::Packer;

our $VERSION = '0.01';
use Carp ();

our $BUFFER_SIZE = 1024*1024;

1;
__END__

=encoding utf8

=head1 NAME

Archive::Zip::Uncompressed -

=head1 SYNOPSIS

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


=head1 DESCRIPTION

Archive::Zip::Uncompressed is uncompressed zip generator for Perl.
This module is useful for packing JPEG, MP3, and other compressed data.

=head1 FAQ

=over 4

=item Do you know Archive::Zip?

Yes.

L<Archive::Zip> is awesome library for handling zip archive.
But, the module has dependencies for XS.

=back

=head1 AUTHOR

Tokuhiro Matsuno E<lt>tokuhirom AAJKLFJEF GMAIL COME<gt>

=head1 SEE ALSO

L<http://www.pkware.com/documents/casestudies/APPNOTE.TXT>, L<Archive::Zip>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
