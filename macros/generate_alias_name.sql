{% macro generate_alias_name(custom_alias_name=none, node=none) %}

    {%- if custom_alias_name -%}
        {{ custom_alias_name | trim }}

    {%- elif node.name.startswith('int__') -%}
        {{ node.name | replace('int__', '') }}

    {%- elif node.name.startswith('mart__') -%}
        {{ node.name | replace('mart__', '') }}
        
    {%- else -%}
        {{ node.name }}

    {%- endif -%}

{% endmacro %}
