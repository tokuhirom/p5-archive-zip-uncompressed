use warnings;
use strict;
use 5.00800;

package Archive::Zip::Uncompressed;
our $VERSION = '0.01';
use Carp ();

our $BUFFER_SIZE = 1024*1024;

# little endian

package #
    Archive::Zip::Uncompressed::Packer;
use File::stat;
use Fcntl ':seek';
use constant {
    'HeaderMaker' => 'Archive::Zip::Uncompressed::HeaderMaker',
};

sub new {
    my ($class, $file) = @_;
    my $fh;
    if (ref $file eq 'GLOB' || ref $file eq 'IO') {
        $fh = $file;
    } else {
        open $fh, '>', $file or die "Cannot open archive file: $!";
    }

    bless {
        fh              => $fh,
        central_headers => [],
    }, $class;
}

sub add_file {
    my ($self, $fname) = @_;
    my $header_pos = tell($self->{fh});
    Carp::croak("tell: $fname, $!") if $header_pos == -1;
    my $stat = stat($fname) or die "Cannot call stat: '$fname'";
    open my $ifh, '<', $fname or Carp::croak("Cannot open file: $fname");
    my $crc32 = Archive::Zip::Uncompressed::CRC32->calc_crc32_from_file($ifh);
    seek($ifh, 0, SEEK_SET) or Carp::croak("Cannot seek file: $fname");
    my $header_body = Archive::Zip::Uncompressed::HeaderMaker->make_file_header_body(
        $stat->mtime,
        $crc32,
        $stat->size,
        length($fname),
    );
    print {$self->{fh}} Archive::Zip::Uncompressed::HeaderMaker->make_file_header($header_body);
    print {$self->{fh}} $fname;
    my $read;
    while ($read = read($ifh, my $buf, $Archive::Zip::Uncompressed::BUFFER_SIZE)) {
        print {$self->{fh}} $buf;
    }
    Carp::croak("cannot read from $fname: $!") unless defined $read;
    push @{$self->{central_headers}}, Archive::Zip::Uncompressed::HeaderMaker->make_central_directory_file_header(
        $header_body,
        Archive::Zip::Uncompressed::HeaderMaker::EXTERNAL_ATTR_DIRECTORY(),
        $header_pos,
        $fname,
    );
    return;
}

sub add_directory {
    my ($self, $fname) = @_;
    my $header_pos = tell($self->{fh});
    Carp::croak("tell: $fname, $!") if $header_pos == -1;

    my $stat = stat($fname) or die "Cannot call stat: '$fname'";
    my $crc32 = 0;
    my $header_body = Archive::Zip::Uncompressed::HeaderMaker->make_file_header_body(
        $stat->mtime,
        $crc32,
        0, # size
        length($fname),
    );
    print {$self->{fh}} Archive::Zip::Uncompressed::HeaderMaker->make_file_header($header_body);
    print {$self->{fh}} $fname;
    push @{$self->{central_headers}}, Archive::Zip::Uncompressed::HeaderMaker->make_central_directory_file_header(
        $header_body,
        Archive::Zip::Uncompressed::HeaderMaker::EXTERNAL_ATTR_DIRECTORY(),
        $header_pos,
        $fname,
    );
    return;
}

sub close {
    my $self = shift;
    Carp::croak("do not call close() twice") if $self->{closed}++;

    my $startpos = tell($self->{fh});
    Carp::croak("tell: $!") if $startpos == -1;

    for my $cheader (@{$self->{central_headers}}) {
        print {$self->{fh}} $cheader;
    }

    my $endpos = tell($self->{fh});
    Carp::croak("tell: $!") if $endpos == -1;

    my $end = Archive::Zip::Uncompressed::HeaderMaker->make_end_central_directory_header(
        scalar(@{$self->{central_headers}}),
        $endpos - $startpos,
        $startpos,
    );
    print {$self->{fh}} $end;

    close($self->{fh});
}

sub DESTROY {
    my $self = shift;
    $self->close() unless $self->{closed};
}

package # hide from pause
    Archive::Zip::Uncompressed::HeaderMaker;

use constant {
    EXTERNAL_ATTR_DIRECTORY => ((040755 << 16) | 0x10),
    EXTERNAL_ATTR_FILE      => 0100644 << 16,
};

sub pack_16 { pack('v', $_[0]) }
sub pack_32 { pack('V', $_[0]) }

sub make_file_header {
    my ($self, $header_body) = @_;
    join(
        '',
        "PK\x03\x04",          # int signature
        $header_body,
    );
}

# @args $time unix time
sub make_file_header_body {
    my ($class, $time, $crc32, $size, $fnamelen) = @_;
    Carp::croak("too large file") if $size > 0xFFFFFFFF; # really?
    Carp::croak("too long file name") if $fnamelen > 0xFFFF;

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($time);
    my $dosdate = (($year+1900-1980)<<9) | ($mon+1)<<5 | $mday;
    my $dostime = ($hour<<11) | ($min<<5) | ($sec>>1);
    my $extralen = 0;

    return join(
        '',
        pack_16(0x14),         # short needver
        pack_16(0),            # short option
        pack_16(0),            # short comptype
        pack_16($dostime),     # short filetime
        pack_16($dosdate),     # short filedate
        pack_32($crc32),       # int crc32
        pack_32($size),        # int compsize
        pack_32($size),        # int uncompsize
        pack_16($fnamelen),    # short fnamelen
        pack_16(0),            # short extralen
    );
}

sub make_central_directory_file_header {
    my ($class, $file_header_body, $external_attr, $header_pos, $fname) = @_;
    return join(
        '',
        "\x50\x4B\x01\x02", # unsigned int signature;
        pack_16(0x0314),    # unsigned short madever;
        $file_header_body,
        pack_16(0), # unsigned short commentlen;
        pack_16(0), # unsigned short disknum;
        pack_16(0), # unsigned short inattr;
        pack_32($external_attr), # unsigned int outattr;
        pack_32($header_pos), # unsigned int headerpos;
        $fname,
    );
}

# $member_num is the number of members
# $dirsize is the sum of length of central directory headers
sub make_end_central_directory_header {
    my ($class, $member_num, $dirsize, $startpos) = @_;
    join(
        '' => (
            "\x50\x4B\x05\x06",    # unsigned int signature;
            pack_16(0),            # unsigned short disknum;
            pack_16(0),            # unsigned short startdisknum;
            pack_16($member_num),  # unsigned short diskdirentry;
            pack_16($member_num),  # unsigned short direntry;
            pack_32($dirsize),     # unsigned int dirsize;
            pack_32($startpos),    # unsigned int startpos;
            pack_16(0),            # unsigned short commentlen;
        )
    );
}

package # hide from pause
    Archive::Zip::Uncompressed::CRC32;

our @CRCTABLE = (
    0x0,        0x77073096, 0xEE0E612C, 0x990951BA, 0x76DC419,  0x706AF48F,
    0xE963A535, 0x9E6495A3, 0xEDB8832,  0x79DCB8A4, 0xE0D5E91E, 0x97D2D988,
    0x9B64C2B,  0x7EB17CBD, 0xE7B82D07, 0x90BF1D91, 0x1DB71064, 0x6AB020F2,
    0xF3B97148, 0x84BE41DE, 0x1ADAD47D, 0x6DDDE4EB, 0xF4D4B551, 0x83D385C7,
    0x136C9856, 0x646BA8C0, 0xFD62F97A, 0x8A65C9EC, 0x14015C4F, 0x63066CD9,
    0xFA0F3D63, 0x8D080DF5, 0x3B6E20C8, 0x4C69105E, 0xD56041E4, 0xA2677172,
    0x3C03E4D1, 0x4B04D447, 0xD20D85FD, 0xA50AB56B, 0x35B5A8FA, 0x42B2986C,
    0xDBBBC9D6, 0xACBCF940, 0x32D86CE3, 0x45DF5C75, 0xDCD60DCF, 0xABD13D59,
    0x26D930AC, 0x51DE003A, 0xC8D75180, 0xBFD06116, 0x21B4F4B5, 0x56B3C423,
    0xCFBA9599, 0xB8BDA50F, 0x2802B89E, 0x5F058808, 0xC60CD9B2, 0xB10BE924,
    0x2F6F7C87, 0x58684C11, 0xC1611DAB, 0xB6662D3D, 0x76DC4190, 0x1DB7106,
    0x98D220BC, 0xEFD5102A, 0x71B18589, 0x6B6B51F,  0x9FBFE4A5, 0xE8B8D433,
    0x7807C9A2, 0xF00F934,  0x9609A88E, 0xE10E9818, 0x7F6A0DBB, 0x86D3D2D,
    0x91646C97, 0xE6635C01, 0x6B6B51F4, 0x1C6C6162, 0x856530D8, 0xF262004E,
    0x6C0695ED, 0x1B01A57B, 0x8208F4C1, 0xF50FC457, 0x65B0D9C6, 0x12B7E950,
    0x8BBEB8EA, 0xFCB9887C, 0x62DD1DDF, 0x15DA2D49, 0x8CD37CF3, 0xFBD44C65,
    0x4DB26158, 0x3AB551CE, 0xA3BC0074, 0xD4BB30E2, 0x4ADFA541, 0x3DD895D7,
    0xA4D1C46D, 0xD3D6F4FB, 0x4369E96A, 0x346ED9FC, 0xAD678846, 0xDA60B8D0,
    0x44042D73, 0x33031DE5, 0xAA0A4C5F, 0xDD0D7CC9, 0x5005713C, 0x270241AA,
    0xBE0B1010, 0xC90C2086, 0x5768B525, 0x206F85B3, 0xB966D409, 0xCE61E49F,
    0x5EDEF90E, 0x29D9C998, 0xB0D09822, 0xC7D7A8B4, 0x59B33D17, 0x2EB40D81,
    0xB7BD5C3B, 0xC0BA6CAD, 0xEDB88320, 0x9ABFB3B6, 0x3B6E20C,  0x74B1D29A,
    0xEAD54739, 0x9DD277AF, 0x4DB2615,  0x73DC1683, 0xE3630B12, 0x94643B84,
    0xD6D6A3E,  0x7A6A5AA8, 0xE40ECF0B, 0x9309FF9D, 0xA00AE27,  0x7D079EB1,
    0xF00F9344, 0x8708A3D2, 0x1E01F268, 0x6906C2FE, 0xF762575D, 0x806567CB,
    0x196C3671, 0x6E6B06E7, 0xFED41B76, 0x89D32BE0, 0x10DA7A5A, 0x67DD4ACC,
    0xF9B9DF6F, 0x8EBEEFF9, 0x17B7BE43, 0x60B08ED5, 0xD6D6A3E8, 0xA1D1937E,
    0x38D8C2C4, 0x4FDFF252, 0xD1BB67F1, 0xA6BC5767, 0x3FB506DD, 0x48B2364B,
    0xD80D2BDA, 0xAF0A1B4C, 0x36034AF6, 0x41047A60, 0xDF60EFC3, 0xA867DF55,
    0x316E8EEF, 0x4669BE79, 0xCB61B38C, 0xBC66831A, 0x256FD2A0, 0x5268E236,
    0xCC0C7795, 0xBB0B4703, 0x220216B9, 0x5505262F, 0xC5BA3BBE, 0xB2BD0B28,
    0x2BB45A92, 0x5CB36A04, 0xC2D7FFA7, 0xB5D0CF31, 0x2CD99E8B, 0x5BDEAE1D,
    0x9B64C2B0, 0xEC63F226, 0x756AA39C, 0x26D930A,  0x9C0906A9, 0xEB0E363F,
    0x72076785, 0x5005713,  0x95BF4A82, 0xE2B87A14, 0x7BB12BAE, 0xCB61B38,
    0x92D28E9B, 0xE5D5BE0D, 0x7CDCEFB7, 0xBDBDF21,  0x86D3D2D4, 0xF1D4E242,
    0x68DDB3F8, 0x1FDA836E, 0x81BE16CD, 0xF6B9265B, 0x6FB077E1, 0x18B74777,
    0x88085AE6, 0xFF0F6A70, 0x66063BCA, 0x11010B5C, 0x8F659EFF, 0xF862AE69,
    0x616BFFD3, 0x166CCF45, 0xA00AE278, 0xD70DD2EE, 0x4E048354, 0x3903B3C2,
    0xA7672661, 0xD06016F7, 0x4969474D, 0x3E6E77DB, 0xAED16A4A, 0xD9D65ADC,
    0x40DF0B66, 0x37D83BF0, 0xA9BCAE53, 0xDEBB9EC5, 0x47B2CF7F, 0x30B5FFE9,
    0xBDBDF21C, 0xCABAC28A, 0x53B39330, 0x24B4A3A6, 0xBAD03605, 0xCDD70693,
    0x54DE5729, 0x23D967BF, 0xB3667A2E, 0xC4614AB8, 0x5D681B02, 0x2A6F2B94,
    0xB40BBE37, 0xC30C8EA1, 0x5A05DF1B, 0x2D02EF8D
);

sub calc_crc32_from_string {
    my ($class, $src, $result) = @_;
    $result = 0xFFFFFFFF unless defined $result;
    for my $c (split //, $src) {
        $result = ($result >> 8) ^ $CRCTABLE[ord($c) ^ ($result & 0xFF)];
    }
    return (~$result) & 0xFFFFFFFF;
}

sub calc_crc32_from_file {
    my ($class, $fh) = @_;
    my $result = 0xFFFFFFFF;
    my $read;
    while ($read = read($fh, my $buf, $Archive::Zip::Uncompressed::BUFFER_SIZE)) {
        $result = $class->calc_crc32_from_string($buf, $result);
    }
    Carp::croak("cannot read from file: $!") unless defined $read;
    return $result;
}

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

Archive::Zip::Uncompressed is

=head1 AUTHOR

Tokuhiro Matsuno E<lt>tokuhirom AAJKLFJEF GMAIL COME<gt>

=head1 SEE ALSO

L<http://www.pkware.com/documents/casestudies/APPNOTE.TXT>, L<Archive::Zip>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
