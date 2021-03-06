require "minitest/autorun"
require "nidyx" # we use some core_ext stuff that requires this
require "nidyx/parser"

class TestParser < Minitest::Test
  def test_description
    schema = {
      "type" => "object",
      "properties" => {
        "key" => {
          "description" => "a description",
          "type" => "string"
        },
        "value" => { "type" => "integer" }
      }
    }

    models = parse(schema)
    props = models["TSModel"].properties
    key = props.shift
    assert_equal("a description", key.description)
    assert_equal(:string, key.type)
    assert_equal("key", key.name)
    assert_equal(true, key.optional)
    value = props.shift
    assert_equal(:integer, value.type)
    assert_equal("value", value.name)
    assert_equal(true, value.optional)
  end

  def test_nested_properties
    schema = {
      "type" => "object",
      "properties" => {
        "key" => { "type" => "string" },
        "value" => {
          "type" => "object",
          "properties" => {
            "name" => { "type" => "string" },
            "obj" => {
              "type" => "object",
              "properties" => {
                "data" => { "type" => "string" }
              }
            }
          }
        }
      }
    }

    models = parse(schema)

    # root model
    model = models["TSModel"]
    assert_deps(%w(TSValueModel), model)
    props = model.properties
    key = props.shift
    assert_equal("key", key.name)
    assert_equal(:string, key.type)
    value = props.shift
    assert_equal("value", value.name)
    assert_equal(:object, value.type)
    assert_equal("TSValueModel", value.class_name)
    assert_equal(true, value.has_properties?)

    # value model
    model = models["TSValueModel"]
    assert_deps(%w(TSValueObjModel), model)
    props = model.properties
    name = props.shift
    assert_equal("name", name.name)
    assert_equal(:string, name.type)
    obj = props.shift
    assert_equal("obj", obj.name)
    assert_equal(:object, obj.type)
    assert_equal("TSValueObjModel", obj.class_name)

    # value obj model
    data = models["TSValueObjModel"].properties.shift
    assert_equal("data", data.name)
    assert_equal(:string, data.type)
  end

  def test_definitions
    schema = {
      "type" => "object",
      "properties" => {
        "value" =>  { "$ref" => "#/definitions/obj" },
      },
      "definitions" => {
        "obj" => {
          "type" => "object",
          "properties" => {
            "banner" => { "$ref" => "#/definitions/banner" },
            "count" => { "type" => "integer" }
          }
        },
        "banner" => { "type" => "string" }
      }
    }

    models = parse(schema)

    # root model
    model = models["TSModel"]
    assert_deps(%w(TSObjModel), model)
    props = model.properties
    value = props.shift
    assert_equal("value", value.name)
    assert_equal(:object, value.type)
    assert_equal("TSObjModel", value.class_name)

    # obj model
    model = models["TSObjModel"]
    props = model.properties
    banner = props.shift
    assert_equal("banner", banner.name)
    assert_equal(:string, banner.type)
    count = props.shift
    assert_equal("count", count.name)
    assert_equal(:integer, count.type)
  end

  def test_simple_chained_refs
    schema = {
      "type" => "object",
      "properties" => {
        "value1" => { "$ref" => "#/definitions/value2" }
      },
      "definitions" => {
        "value2" => { "$ref" => "#/definitions/value3" },
        "value3" => { "type" => "string" }
      }
    }

    models = parse(schema)
    model = models["TSModel"]
    assert_deps([], model)
    props = model.properties
    value1 = props.shift
    assert_equal(:string, value1.type)
    assert_equal("value1", value1.name)
  end

  def test_chained_refs_to_an_object
    schema = {
      "type" => "object",
      "properties" => {
        "value1" => { "$ref" => "#/definitions/value2" }
      },
      "definitions" => {
        "value2" => { "$ref" => "#/definitions/value3" },
        "value3" => {
          "type" => "object",
          "properties" => {
            "value4" => { "type" => "string" }
          }
        }
      }
    }

    models = parse(schema)

    # root model
    model = models["TSModel"]
    assert_deps(%w(TSValue3Model), model)
    props = model.properties
    value1 = props.shift
    assert_equal("value1", value1.name)
    assert_equal(:object, value1.type)
    assert_equal("TSValue3Model", value1.class_name)

    # mid ref
    assert_equal(nil, models["TSValue2Model"]) # should never exist

    # end ref
    props = models["TSValue3Model"].properties
    value4 = props.shift
    assert_equal("value4", value4.name)
    assert_equal(:string, value4.type)
  end

  def test_array_lookups
    schema = {
      "type" => "object",
      "properties" => {
        "string_array" => {
          "type" => "array",
          "items" => ["string", "null"]
        },
        "object_array" => {
          "type" => "array",
          "items" => { "$ref" => "#/definitions/object" }
        },
        "multi_object_array" => {
          "type" => "array",
          "items" => [
            { "$ref" => "#/definitions/object" },
            { "$ref" => "#/definitions/other_object" },
            { "type" => "string" }
          ]
        }
      },
      "definitions" => {
        "object" => {
          "type" => "object",
          "required" => ["int_value"],
          "properties" => {
            "int_value" => { "type" => "integer" }
          }
        },
        "other_object" => {
          "type" => "object",
          "properties" => {
            "string_value" => { "type" => "string" }
          }
        }
      }
    }

    models = parse(schema)
    assert_equal(3, models.size)

    # root model
    model = models["TSModel"]
    assert_deps(%w(TSObjectModel TSOtherObjectModel string), model)
    props = model.properties

    string_array = props.shift
    assert_equal(:array, string_array.type)
    assert_equal([], string_array.collection_types)

    object_array = props.shift
    assert_equal(:array, object_array.type)
    assert_equal(["TSObjectModel"], object_array.collection_types)

    multi_object_array = props.shift
    assert_equal(:array, multi_object_array.type)
    assert_equal(%w(TSObjectModel TSOtherObjectModel string), multi_object_array.collection_types)

    # object model
    model = models["TSObjectModel"]
    props = model.properties
    int_value = props.shift
    assert_equal(:integer, int_value.type)
    assert_equal("intValue", int_value.name)

    # other object model
    model = models["TSOtherObjectModel"]
    props = model.properties
    string_value = props.shift
    assert_equal(:string, string_value.type)
    assert_equal("stringValue", string_value.name)
  end

  def test_object_with_type_array
    schema = {
      "type" => "object",
      "properties" => {
        "value" => {
          "type" => ["object", "null"],
          "properties" => {
            "value" => { "type" => "string" }
          }
        }
      }
    }

    models = parse(schema)
    model = models["TSModel"]
    props = model.properties

    value = props.shift
    assert_equal(Set.new([:object, :null]), value.type)
    assert_equal("TSValueModel", value.class_name)

    model = models["TSValueModel"]
    props = model.properties
    value = props.shift
    assert_equal("value", value.name)
    assert_equal(:string, value.type)
  end

  def test_anonymous_object
    schema = {
      "type" => "object",
      "properties" => {
        "value" => { "type" => "object" }
      }
    }

    models = parse(schema)
    model = models["TSModel"]
    props = model.properties
    value = props.shift
    assert_equal(true, model.dependencies.empty?)
    assert_equal(:object, value.type)
    assert_equal(false, value.has_properties?)
  end

  def test_anonymous_array
    schema = {
      "type" => "object",
      "properties" => {
        "value" => { "type" => "array" }
      }
    }

    models = parse(schema)
    model = models["TSModel"]
    props = model.properties
    value = props.shift
    assert_equal(:array, value.type)
  end

  def test_model_name_override
    schema = {
      "type" => "object",
      "properties" => {
        "value" => {
          "type" => "object",
          "nameOverride" => "something",
          "properties" => {
            "name" => { "$ref" => "#/definitions/obj" }
          }
        }
      },
      "definitions" => {
        "obj" => {
          "type" => "object",
          "nameOverride" => "somethingElse",
          "properties" => {
            "recObject" => {
              "type" => "object",
              "nameOverride" => "rec",
              "properties" => {
                "value" => { "type" => "string" }
              }
            }
          }
        }
      }
    }

    models = parse(schema)
    assert_equal(4, models.size)

    # root model
    model = models["TSModel"]
    props = model.properties
    value = props.shift
    assert_equal("TSSomethingModel", value.class_name)

    # something model
    model = models["TSSomethingModel"]
    props = model.properties
    value = props.shift
    assert_equal("TSSomethingElseModel", value.class_name)

    # something else model
    model = models["TSSomethingElseModel"]
    assert_equal("TSSomethingElseModel", model.name)

    # rec model
    model = models["TSRecModel"]
    assert_equal("TSRecModel", model.name)
  end

  def test_property_name_override
    schema = {
      "type" => "object",
      "properties" => {
        "name" => {
          "type" => "string",
          "nameOverride" => "otherName"
        }
      }
    }

    models = parse(schema)
    assert_equal(1, models.size)
    model = models["TSModel"]
    props = model.properties
    otherName = props.shift
    assert_equal("otherName", otherName.name)
    assert_equal(:string, otherName.type)
  end

  def test_array_top_level_object
    schema = {
      "type" => "array",
      "items" => { "$ref" => "#/definitions/object" },
      "definitions" => {
        "object" => {
          "type" => "object",
          "properties" => {
            "text" => { "type" => "string" }
          }
        }
      }
    }

    models = parse(schema)
    assert_equal(1, models.size)
    model = models["TSObjectModel"]
    text = model.properties.shift
    assert_equal("text", text.name)
    assert_equal(:string, text.type)
  end

  def test_array_top_level_object_multiple_types
    schema = {
      "type" => "array",
      "items" => [
        { "$ref" => "#/definitions/object" },
        { "$ref" => "#/definitions/otherObject" }
      ],
      "definitions" => {
        "object" => {
          "type" => "object",
          "properties" => {
            "text" => { "type" => "string" }
          }
        },
        "otherObject" => {
          "type" => "object",
          "properties" => {
            "bool" => { "type" => "boolean" }
          }
        }
      }
    }

    models = parse(schema)
    assert_equal(2, models.size)

    model = models["TSObjectModel"]
    text = model.properties.shift
    assert_equal("text", text.name)
    assert_equal(:string, text.type)

    model = models["TSOtherObjectModel"]
    bool = model.properties.shift
    assert_equal("bool", bool.name)
    assert_equal(:boolean, bool.type)
  end

  def test_any_of_array
    schema = {
      "type" => "object",
      "properties" => {
        "widgets" => {
          "type" => "array",
          "items" => {
            "anyOf" => [
              { "$ref" => "#/definitions/object" },
              { "$ref" => "#/definitions/otherObject" }
            ]
          }
        }
      },
      "definitions" => {
        "object" => {
          "type" => "object",
          "properties" => {
            "count" => { "type" => "integer" }
          }
        },
        "otherObject" => {
          "type" => "object",
          "properties" => {
            "lastObject" => { "$ref" => "#/definitions/lastObject" }
          }
        },
        "lastObject" => {
          "type" => "object",
          "properties" => {
            "limit" => { "type" => "integer" }
          }
        }
      }
    }

    models = parse(schema)
    assert_equal(4, models.size)

    # root model
    props = models["TSModel"].properties
    value = props.shift
    assert_equal(:array, value.type)

    # object model
    props = models["TSObjectModel"].properties
    value = props.shift
    assert_equal(:integer, value.type)

    # other object model
    props = models["TSOtherObjectModel"].properties
    value = props.shift
    assert_equal("TSLastObjectModel", value.class_name)

    # last object model
    props = models["TSLastObjectModel"].properties
    value = props.shift
    assert_equal(:integer, value.type)
  end

  private

  OPTIONS = {
    :class_prefix => "TS"
  }

  def assert_deps(expected, model)
    actual = model.dependencies
    assert_equal(Set.new(expected), actual)
  end

  def parse(schema)
    Nidyx::Parser.parse(schema, OPTIONS)
  end
end
