package Archive::Zip::Uncompressed::Unpacker;
use File::stat;
use Fcntl ':seek';
use constant {
    HEADER_SIZE         => 30,
    CENTRAL_HEADER_SIZE => 46,
    END_HEADER_SIZE     => 22,
};

sub unpack_16 { unpack 'v', shift }
sub unpack_32 { unpack 'V', shift }

sub new {
    my ($class, $file) = @_;
    my $fh;
    if (ref $file eq 'GLOB' || ref $file eq 'IO') {
        $fh = $file;
    } else {
        open $fh, '<', $file or die "Cannot open archive file: $!";
    }

    # read END header
    my $size = -s $file;
    seek($fh, -(END_HEADER_SIZE), SEEK_END) or Carp::croak("seek to end header: $!");
    read($fh, my $end_cent_buf, END_HEADER_SIZE) == END_HEADER_SIZE or Carp::croak("cannot read end header");
    substr($end_cent_buf, 0, 4) eq "\x50\x4B\x05\x06" or Carp::croak("invalid end-of-central-directory-header");
    my $member_num = unpack_16(substr($end_cent_buf,  8, 2));
    my $dirsize    = unpack_16(substr($end_cent_buf, 12, 4));
    my $startpos   = unpack_16(substr($end_cent_buf, 16, 4));
        #  0 "\x50\x4B\x05\x06",    # unsigned int signature;
        #  4 pack_16(0),            # unsigned short disknum;
        #  6 pack_16(0),            # unsigned short startdisknum;
        #  8 pack_16($member_num),  # unsigned short diskdirentry;
        # 10 pack_16($member_num),  # unsigned short direntry;
        # 12 pack_32($dirsize),     # unsigned int dirsize;
        # 16 pack_32($startpos),    # unsigned int startpos;
        # 20 pack_16(0),            # unsigned short commentlen;

    my $self = bless {
        fh              => $fh,
        size            => $size,
        member_num      => $member_num,
        dirsize         => $dirsize,
        startpos        => $startpos,
        idx             => 0,
        next_central    => $startpos,
    }, $class;
    return $self;
}

sub next {
    my ($self) = @_;
    my $idx = $self->{idx}++;
    return if $idx >= $self->{member_num};

    # seek to head of central header
    seek($self->{fh}, $self->{next_central}, SEEK_SET) or Carp::croak("seek: $!");
    read($self->{fh}, my $buf, CENTRAL_HEADER_SIZE) == CENTRAL_HEADER_SIZE or Carp::croak("cannot seek");
    if ( substr( $buf, 0, 4 ) ne "\x50\x4B\x01\x02" ) {
        Carp::confess(
            sprintf( "invalid header signature: %08X ne %08X",
                unpack_32( "\x50\x4B\x01\x02" ),
                unpack_32( substr( $buf, 0, 4 ) ) )
        );
    }
    my $dosdt = substr( $buf, 12, 4 );
    my $size       = unpack_32( substr( $buf, 20, 4 ) );
    my $fname_len  = unpack_16( substr( $buf, 28, 2 ) );
    my $external_file_attributes   = unpack_32( substr( $buf, 38, 4 ) );
    my $header_pos = unpack_32( substr( $buf, 42, 4 ) );
    read($self->{fh}, my $fname, $fname_len)==$fname_len or Carp::croak("cannot read file name from file");

      # 0  "\x50\x4B\x01\x02", # unsigned int signature;
      # 4  pack_16(0x0314),    # unsigned short madever;
      # 6  pack_16(0x14),         # short needver
      # 8  pack_16(0),            # short option
      # 10 pack_16(0),            # short comptype
      # 12 pack_16($dostime),     # short filetime
      # 14 pack_16($dosdate),     # short filedate
      # 16 pack_32($crc32),       # int crc32
      # 20 pack_32($size),        # int compsize
      # 24 pack_32($size),        # int uncompsize
      # 28 pack_16($fnamelen),    # short fnamelen
      # 30 pack_16(0),            # short extralen
      # 32 pack_16(0), # unsigned short commentlen;
      # 34 pack_16(0), # unsigned short disknum;
      # 36 pack_16(0), # unsigned short inattr;
      # 38 pack_32($external_attr), # unsigned int outattr;
      # 42 pack_32($header_pos), # unsigned int headerpos;

    $self->{next_central} = $self->{next_central} + CENTRAL_HEADER_SIZE + $fname_len;

    return Archive::Zip::Uncompressed::Unpacker::Member->new(
        fh         => $self->{fh},
        external_file_attributes   => $external_file_attributes,
        size       => $size,
        header_pos => $header_pos,
        filename   => $fname,
        fname_len  => $fname_len,
        'pos'      => $header_pos + HEADER_SIZE + $fname_len,
    );
}

package #
    Archive::Zip::Uncompressed::Unpacker::Member;
use Fcntl ':seek';

sub new {
    my $class = shift;
    bless {@_}, $class;
}

# $self->read(my $buf, $bufsiz)
sub read {
    my $self = $_[0];
    seek($self->{fh}, $self->{pos}, SEEK_SET) or Carp::croak("cannot seek: $!");
    my $buflen = $_[2];
    if ( $self->{header_pos} +
        Archive::Zip::Uncompressed::Unpacker::HEADER_SIZE() +
        $self->{fname_len} +
        $self->{size} < $self->{pos} +
        $buflen )
    {
        $buflen =
          ( $self->{header_pos} +
              Archive::Zip::Uncompressed::Unpacker::HEADER_SIZE() +
              $self->{fname_len} +
              $self->{size} ) - $self->{pos};
    }
    read($self->{fh}, $_[1], $buflen);
}

BEGIN {
    no strict 'refs';
    for (qw/external_file_attributes size filename/) {
        my $key = $_;
        *{__PACKAGE__ . '::' . $_ } = sub { $_[0]->{$key} }
    }
}

1;
