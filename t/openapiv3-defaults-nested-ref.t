use lib '.';
use t::Helper;
use JSON::Validator::Schema::OpenAPIv3;
use Test::Deep;
use Test::More;

my %params = (get_req => [], get_params => [], set_params => []);
my $schema
  = JSON::Validator::Schema::OpenAPIv3->new->data('data://main/defaults.json');
my $c = t::Helper->controller(\%params);
note 'default in body';
{
  $params{get_req} = [
    {
      in     => 'body',
      name   => 'body',
      content_type => 'application/json',
      exists => 1,
      value =>
        {id => 42, name => 'Goma', toy => {id => 42, name => 'Little red'}}
    },
  ];
  my @errors = $schema->validate_request($c, post => '/pets');
  is_deeply \@errors, [], 'valid request';
  cmp_deeply(
    $params{get_req},
    [
      superhashof({
        in    => 'body',
        name  => 'body',
        value => {
          id   => 42,
          name => 'Goma',
          tag  => 'Mouse',
          toy  => {id => 42, name => 'Little red', type => 'chewchew'}
        },
      }),
    ],
    'default set in body param',
  );
}

note 'defaults in deeply nested body';
{
  $params{get_req} = [
    {
      in     => 'body',
      name   => 'body',
      content_type => 'application/json',
      exists => 1,
      value  => {
        id   => 42,
        name => 'Goma',
        toy  => {id => 42, name => 'Little red', origin => {}}
      }
    },
  ];
  my @errors = $schema->validate_request($c, post => '/pets');
  is_deeply \@errors, [], 'valid request';
  cmp_deeply(
    $params{get_req},
    [
      superhashof({
        in    => 'body',
        name  => 'body',
        value => {
          id   => 42,
          name => 'Goma',
          tag  => 'Mouse',
          toy  => {
            id     => 42,
            name   => 'Little red',
            type   => 'chewchew',
            origin => {manufacturer => 'UNKNOWN'}
          }
        },
      }),
    ],
    'default set in body param',
  );
}

done_testing;

__DATA__
@@ defaults.json
{
  "openapi": "3.0.0",
  "info": {
    "version": "1.0.0",
    "title": "Swagger Petstore",
    "contact": {
      "name": "OAI",
      "url": "https://raw.githubusercontent.com/OAI/OpenAPI-Specification/master/examples/v2.0/json/petstore.json"
    },
    "license": {
      "name": "MIT"
    }
  },
  "paths": {
    "/pets": {
      "get": {
        "summary": "List all pets",
        "operationId": "listPets",
        "tags": [
          "pets"
        ],
        "parameters": [
          {
            "name": "limit",
            "in": "query",
            "description": "How many items to return at one time (max 100)",
            "required": false,
            "schema": {
              "type": "integer",
              "format": "int32",
              "default": 42
            }
          }
        ],
        "responses": {
          "201": {
            "description": "Null response"
          }
        }
      },
      "post": {
        "summary": "Create a pet",
        "operationId": "createPets",
        "tags": [
          "pets"
        ],
        "requestBody": {
          "content": {
            "application/json": {
              "schema": {
                "$ref": "#/components/schemas/Pet"
              }
            }
          },
          "required": true
        },
        "responses": {
          "201": {
            "description": "Null response"
          }
        }
      }
    }
  },
  "servers": [
    {
      "url": "http://petstore.swagger.io/v1"
    }
  ],
  "components": {
    "schemas": {
      "Pet": {
        "required": [
          "id",
          "name"
        ],
        "properties": {
          "id": {
            "type": "integer",
            "format": "int64"
          },
          "name": {
            "type": "string"
          },
          "tag": {
            "type": "string",
            "default": "Mouse"
          },
          "toy": {
            "$ref": "#/components/schemas/Toy"
          }
        }
      },
      "Toy": {
        "required": [
          "id",
          "name"
        ],
        "properties": {
          "id": {
            "type": "integer",
            "format": "int64"
          },
          "name": {
            "type": "string"
          },
          "type": {
            "type": "string",
            "enum": [
              "ball",
              "stick",
              "chewchew"
            ],
            "default": "chewchew"
          },
          "origin": {
            "$ref": "#/components/schemas/Origin"
          }
        }
      },
      "Origin": {
        "properties": {
          "country": {
            "type": "string"
          },
          "manufacturer": {
            "type": "string",
            "default": "UNKNOWN"
          }
        }
      },
      "Pets": {
        "type": "array",
        "items": {
          "$ref": "#/components/schemas/Pet"
        }
      }
    }
  }
}