package JSON::Validator::Schema::OpenAPIv2;
use Mojo::Base 'JSON::Validator::Schema';

use JSON::Validator::Util qw(E json_pointer);
use Mojo::URL;
use Scalar::Util 'looks_like_number';
use Time::Local ();

use constant DEBUG => $ENV{JSON_VALIDATOR_DEBUG} || 0;

our %COLLECTION_RE
  = (pipes => qr{\|}, csv => qr{,}, ssv => qr{\s}, tsv => qr{\t});

has allow_invalid_ref => 0;

has default_response_schema => sub {
  return {
    type       => 'object',
    required   => ['errors'],
    properties => {
      errors => {
        type  => 'array',
        items => {
          type     => 'object',
          required => ['message'],
          properties =>
            {message => {type => 'string'}, path => {type => 'string'}}
        },
      },
    },
  };
};

has errors => sub {
  my $self = shift;
  my $clone
    = $self->new(%$self, allow_invalid_ref => 0)->data($self->specification);
  my @errors = $clone->validate($self->data);

  $self->get(
    ['paths', undef, undef, 'parameters'],
    sub {
      push @errors, E $_[1], 'Only one parameter can have "in":"body"'
        if +(grep { $_->{in} eq 'body' } @{$_[0] || []}) > 1;
    }
  );

  return \@errors;
};

has specification => 'http://swagger.io/v2/schema.json';

sub base_url {
  my $self = shift;
  my $data = $self->data;

  # Set
  if (@_) {
    my $url = Mojo::URL->new(shift);
    $data->{schemes}[0] = $url->scheme    if $url->scheme;
    $data->{host}       = $url->host_port if $url->host_port;
    $data->{basePath}   = $url->path      if $url->path;
    return $self;
  }

  # Get
  my $url     = Mojo::URL->new;
  my $schemes = $data->{schemes} || [];
  $url->scheme($schemes->[0] || 'http');

  my ($host, $port) = split ':', ($data->{host} || '');
  $url->host($host) if length $host;
  $url->port($port) if length $port;

  $url->path($data->{basePath}) if $data->{basePath};

  return $url;
}

sub data {
  my $self = shift;
  return $self->{data} ||= {} unless @_;

  if ($self->allow_invalid_ref) {
    my $clone = $self->new(%$self, allow_invalid_ref => 0);
    $self->{data} = $clone->data(shift)->bundle({replace => 1})->data;
  }
  else {
    $self->{data} = $self->_resolve(shift);
  }

  if (my $class = $self->version_from_class) {
    my $version = $class->can('VERSION') && $class->VERSION;
    $self->{data}{info}{version} = "$version" if length $version;
  }

  delete $self->{errors};
  delete $self->{find_all_nodes_cache};
  return $self;
}

sub ensure_default_response {
  my ($self, $params) = @_;

  my $name       = $params->{name} || 'DefaultResponse';
  my $def_schema = $self->_sub_schemas->{$name}
    ||= $self->default_response_schema;
  tie my %ref, 'JSON::Validator::Ref', $def_schema,
    json_pointer $self->_sub_schemas_pointer, $name;

  my $codes      = $params->{codes} || [400, 401, 404, 500, 501];
  my $res_schema = $self->_response_schema(\%ref);
  $self->get(
    ['paths', undef, undef, 'responses'],
    sub { $_[0]->{$_} ||= $res_schema for @$codes },
  );

  delete $self->{errors};
  return $self;
}

sub find_all_nodes {
  my ($self, $pointer, $leaf) = @_;
  my @found;
  push @found, $self->data->{$leaf} if exists $self->data->{$leaf};

  my @path;
  for my $p (@$pointer) {
    push @path, $p;
    my $node = $self->get([@path]);
    push @found, $node->{$leaf} if exists $node->{$leaf};
  }

  return @found;
}

sub validate_request {
  my ($self, $c, $method, $path) = @_;
  my $parameters = $self->_build_request_parameter_rules($method, $path);
  my $request    = $c->openapi->get_request_data($parameters);

  my @errors = $self->_validate_request_parameters($parameters, $request);
  $c->openapi->set_request_data($request) unless @errors;

  return @errors;
}

sub validate_response { die 'TODO' }

sub version_from_class {
  my $self = shift;
  return $self->{version_from_class} || '' unless @_;

  my $class = shift;
  $self->{version_from_class} = $class;
  $self->{data}{info}{version} = $class->VERSION;
  return $self;
}

sub _build_formats {
  my $self = shift;

  return {
    'binary'    => sub {undef},
    'byte'      => JSON::Validator::Formats->can('check_byte'),
    'date'      => JSON::Validator::Formats->can('check_date'),
    'date-time' => JSON::Validator::Formats->can('check_date_time'),
    'double'    => JSON::Validator::Formats->can('check_double'),
    'email'     => JSON::Validator::Formats->can('check_email'),
    'float'     => JSON::Validator::Formats->can('check_float'),
    'hostname'  => JSON::Validator::Formats->can('check_hostname'),
    'int32'     => JSON::Validator::Formats->can('check_int32'),
    'int64'     => JSON::Validator::Formats->can('check_int64'),
    'ipv4'      => JSON::Validator::Formats->can('check_ipv4'),
    'ipv6'      => JSON::Validator::Formats->can('check_ipv6'),
    'password'  => sub {undef},
    'regex'     => JSON::Validator::Formats->can('check_regex'),
    'uri'       => JSON::Validator::Formats->can('check_uri'),
  };
}

sub _build_request_parameter_rules {
  my ($self, $method, $path) = @_;

  my $cache_key = "$method:$path";
  return $self->{request_parameters}{$cache_key}
    if $self->{request_parameters}{$cache_key};

  my @accepts
    = map {@$_} $self->find_all_nodes([paths => $path, $method], 'consumes');
  my @parameters
    = map {@$_} $self->find_all_nodes([paths => $path, $method], 'parameters');

  for my $param (@parameters) {
    $param->{accepts} = {map { ($_ => $param->{schema}) } @accepts}
      if $param->{in} eq 'body';
  }

  return $self->{request_parameters}{$cache_key} = \@parameters;
}

sub _coerce_by_collection_format {
  my ($self, $data, $p) = @_;
  return $data unless $p->{collectionFormat};

  my $schema = $p->{schema} || $p;
  my $type
    = ($schema->{items} ? $schema->{items}{type} : $schema->{type}) || '';

  if ($p->{collectionFormat} eq 'multi') {
    $data  = [$data] unless ref $data eq 'ARRAY';
    @$data = map { $_ + 0 } @$data if $type eq 'integer' or $type eq 'number';
    return $data;
  }

  my $re     = $COLLECTION_RE{$p->{collectionFormat}} || ',';
  my $single = ref $data eq 'ARRAY' ? 0 : ($data = [$data]);

  for my $i (0 .. @$data - 1) {
    my @d = split /$re/, ($data->[$i] // '');
    $data->[$i]
      = ($type eq 'integer' or $type eq 'number') ? [map { $_ + 0 } @d] : \@d;
  }

  return $single ? $data->[0] : $data;
}

sub _get_default_value_from_parameter {
  my ($self, $p) = @_;
  return ($p->{schema}{default}, 1)
    if $p->{schema} and exists $p->{schema}{default};
  return ($p->{default}, 1) if exists $p->{default};
  return (undef,         0);
}

sub _param_key {
  return join ':', grep {defined} @{$_[0]}{qw(in name)};
}

sub _prefix_path {
  return join '', "/$_[0]", $_[1] ? ($_[1]) : ();
}

sub _resolve_ref {
  my ($self, $topic, $url) = @_;

# https://github.com/OAI/OpenAPI-Specification/blob/3a29219e07b01be93bcbede32e861e6c5b8e77c3/examples/wordnik/petstore.yaml#L37
  $topic->{'$ref'} = "#/definitions/$topic->{'$ref'}"
    if $topic->{'$ref'} =~ /^\w+$/;

  return $self->SUPER::_resolve_ref($topic, $url);
}

sub _response_schema {
  my ($self, $schema) = @_;
  return {description => 'Default response.', schema => $schema};
}

sub _sub_schemas         { shift->data->{definitions} ||= {} }
sub _sub_schemas_pointer {'#/definitions'}

sub _handle_defaults {
  my ($self, $param, $req) = @_;

    if ($req->{in} eq 'body') {
      my $schema = $self->_get_parameter_schema($param,$req);
      $schema = $self->_ref_to_schema($schema)
        if ref $schema eq 'HASH' and $schema->{'$ref'};

      $self->_handle_defaults_properties($schema->{properties}, $req->{value});

    } else {
        my ($default, $got_default)
          = $self->_get_default_value_from_parameter($param);
        if ( $got_default ) {
          unless ( keys %$req ) {
            $req = {
              in => $param->{in},
              name => $param->{name},
            };
          }
          $req->{value} = $default;
          $req->{exists} = 1;
        }
    }
}

sub _handle_defaults_properties {
  my ($self, $properties, $request_value) = @_;
  while (my ($k, $v) = each %$properties) {
    if (exists $v->{properties}) {
      $self->_handle_defaults_properties($v->{properties},
        $request_value->{$k});
      next;
    }
    my ($default, $got_default) = $self->_get_default_value_from_parameter($v);
    $request_value->{$k} = $default
      if $got_default && !exists $request_value->{$k};
  }
}

sub _get_parameter_schema {
  my ($self, $param, $req) = @_;
  return $param->{schema};
}

sub _validate_request_parameters {
  my ($self, $parameters, $request) = @_;
  my @errors;

  # Make it faster to lookup input values
  $request = {map { (_param_key($_) => $_) } @$request};

  # [in, name, exists, value, content_type] or [in, name, exists, value]
  for my $param (@$parameters) {
    my $req = $request->{_param_key($param)} || {};

    # Handle defaults, unless coerce:defaults enabled (for testing)
    $self->_handle_defaults($param,$req) unless $self->coerce->{defaults};

    if ($param->{required} and !$req->{exists}) {
      push @errors, E "/$param->{name}", [qw(object required)];
    }
    elsif ($req->{exists}) {
      my $schema = $param->{'x-json-schema'} || $param->{schema} || $param;
      push @errors,
        map { $_->path(_prefix_path($param->{name}, $_->path)); $_ }
        $self->validate($req->{value}, $schema);
    }
  }

  return @errors;
}

sub _validate_type_array {
  my ($self, $data, $path, $schema) = @_;

  if (ref $schema->{items} eq 'HASH'
    and ($schema->{items}{type} || '') eq 'array')
  {
    $data = $self->_coerce_by_collection_format($data, $schema->{items});
  }

  return $self->SUPER::_validate_type_array($data, $path, $schema);
}

sub _validate_type_file {
  my ($self, $data, $path, $schema) = @_;

  return unless $schema->{required} and (not defined $data or not length $data);
  return E $path => 'Missing property.';
}

sub _validate_type_object {
  my ($self, $data, $path, $schema) = @_;
  return shift->SUPER::_validate_type_object(@_) unless ref $data eq 'HASH';
  return shift->SUPER::_validate_type_object(@_)
    unless $self->{validate_request};

  my (@errors, %ro);
  for my $name (keys %{$schema->{properties} || {}}) {
    next unless $schema->{properties}{$name}{readOnly};
    push @errors, E "$path/$name", "Read-only." if exists $data->{$name};
    $ro{$name} = 1;
  }

  my $discriminator = $schema->{discriminator};
  if ($discriminator and !$self->{inside_discriminator}) {
    return E $path, "Discriminator $discriminator has no value."
      unless my $name = $data->{$discriminator};
    return E $path, "No definition for discriminator $name."
      unless my $dschema = $self->{root}->get("/definitions/$name");
    local $self->{inside_discriminator} = 1;    # prevent recursion
    return $self->_validate($data, $path, $dschema);
  }

  local $schema->{required} = [grep { !$ro{$_} } @{$schema->{required} || []}];

  return @errors, $self->SUPER::_validate_type_object($data, $path, $schema);
}

1;

=encoding utf8

=head1 NAME

JSON::Validator::Schema::OpenAPIv2 - OpenAPI version 2 / Swagger

=head1 SYNOPSIS

  use JSON::Validator::Schema::OpenAPIv2;
  my $schema = JSON::Validator::Schema::OpenAPIv2->new({...});

  # Validate request against a sub schema
  my $sub_schema = $schema->get("/paths/whatever/get");
  my @errors = $schema->validate_request($c, $sub_schema);
  if (@errors) return $c->render(json => {errors => \@errors}, status => 400);

  # Do your logic inside the controller
  my $res = $c->model->get_stuff;

  # Validate response against a sub schema
  @errors = $schema->validate_response($c, $sub_schema, 200, $res);
  if (@errors) return $c->render(json => {errors => \@errors}, status => 500);

  return $c->render(json => $res);

See L<Mojolicious::Plugin::OpenAPI> for a simpler way of using
L<JSON::Validator::Schema::OpenAPIv2>.

=head1 DESCRIPTION

This class represents L<http://swagger.io/v2/schema.json>.

=head1 ATTRIBUTES

=head2 allow_invalid_ref

  $bool   = $schema->allow_invalid_ref;
  $schema = $schema->allow_invalid_ref(1);

Setting this attribute to a true value, will resolve all the "$ref"s inside the
schema before it is set in L</data>. This can be useful if you don't want to be
restricted by the shortcomings of the OpenAPIv2 specification, but still want a
valid schema.

Note however that circular "$ref"s I<are> not supported by this.

=head2 default_response_schema

  $schema   = $schema->default_response_schema($hash_ref);
  $hash_ref = $schema->default_response_schema;

Holds the structure of the default response schema added by
L</ensure_default_response>.

=head2 errors

  $array_ref = $schema->errors;

Uses L</specification> to validate L</data> and returns an array-ref of
L<JSON::Validator::Error> objects if L</data> contains an invalid schema.

=head2 formats

  $schema   = $schema->formats({});
  $hash_ref = $schema->formats;

Open API support the following formats in addition to the formats defined in
L<JSON::Validator::Schema::Draft4>:

=over 4

=item * byte

A padded, base64-encoded string of bytes, encoded with a URL and filename safe
alphabet. Defined by RFC4648.

=item * date

An RFC3339 date in the format YYYY-MM-DD

=item * double

Cannot test double values with higher precision then what
the "number" type already provides.

=item * float

Will always be true if the input is a number, meaning there is no difference
between  L</float> and L</double>. Patches are welcome.

=item * int32

A signed 32 bit integer.

=item * int64

A signed 64 bit integer. Note: This check is only available if Perl is
compiled to use 64 bit integers.

=back

=head2 specification

  my $str    = $schema->specification;
  my $schema = $schema->specification($str);

Defaults to "L<http://swagger.io/v2/schema.json>".

=head1 METHODS

=head2 base_url

  $schema = $schema->base_url("https://example.com/api");
  $schema = $schema->base_url(Mojo::URL->new("https://example.com/api"));
  $url    = $schema->base_url;

Can either retrieve or set the base URL for this schema. This method will
construct the C<$url> from "/schemes/0", "/host" and "/basePath" in the schema
or set all or some of those attributes from the input URL.

=head2 data

Same as L<JSON::Validator::Schema/data>, but will bundle the schema if
L</allow_invalid_ref> is set, and also change "/data/info/version" if
L</version_from_class> is set.

=head2 ensure_default_response

  $schema = $schema->ensure_default_response({codes => [400, 500], name => "DefaultResponse"});
  $schema = $schema->ensure_default_response;

This method will look through the "responses" definitions in the schema and add
response definitions, unless already defined. The default schema will allow
responses like this:

  {"errors":[{"message:"..."}]}
  {"errors":[{"message:"...","path":"/foo"}]}

=head2 find_all_nodes

  @list = $self->find_all_nodes(\@path, $leaf_name);

Used to find all occcurances of a given C<$leaf_name> while decending down the
specification. Example:

  $self->find_all_nodes([paths => "/pets", "post"], "parameters");

=head2 validate_request

  my @errors = $schema->validate_request($c, $http_method, $api_path);

Used to validate a web request using rules found in L</data> using C<$api_path>
and C<$http_method>. The C<$c> (controller object) need to support this API:

  my $request = $c->openapi->get_request_data(\@parameters);
  $c->openapi->set_request_data($request);

=head2 validate_response

TODO

=head2 version_from_class

  my $str    = $schema->version_from_class;
  my $schema = $schema->version_from_class("My::App");

The class name (if present) will be used to set "/data/info/version" inside the
schame stored in L</data>.

=head1 SEE ALSO

L<JSON::Validator>, L<Mojolicious::Plugin::OpenAPI>,
L<http://openapi-specification-visual-documentation.apihandyman.io/>

=cut
