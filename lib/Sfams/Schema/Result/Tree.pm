package Sfams::Schema::Result::Tree;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

Sfams::Schema::Result::Tree

=cut

__PACKAGE__->table("trees");

=head1 ACCESSORS

=head2 treeid

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 treedesc

  data_type: 'text'
  is_nullable: 1

=head2 treepath

  data_type: 'text'
  is_nullable: 1

=head2 treetype

  data_type: 'enum'
  extra: {list => ["REFERENCE","ALL"]}
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "treeid",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "treedesc",
  { data_type => "text", is_nullable => 1 },
  "treepath",
  { data_type => "text", is_nullable => 1 },
  "treetype",
  {
    data_type => "enum",
    extra => { list => ["REFERENCE", "ALL"] },
    is_nullable => 1,
  },
);
__PACKAGE__->set_primary_key("treeid");

=head1 RELATIONS

=head2 analyses

Type: has_many

Related object: L<Sfams::Schema::Result::Analysis>

=cut

__PACKAGE__->has_many(
  "analyses",
  "Sfams::Schema::Result::Analysis",
  { "foreign.treeid" => "self.treeid" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 family_alltrees

Type: has_many

Related object: L<Sfams::Schema::Result::Family>

=cut

__PACKAGE__->has_many(
  "family_alltrees",
  "Sfams::Schema::Result::Family",
  { "foreign.alltree" => "self.treeid" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 family_reftrees

Type: has_many

Related object: L<Sfams::Schema::Result::Family>

=cut

__PACKAGE__->has_many(
  "family_reftrees",
  "Sfams::Schema::Result::Family",
  { "foreign.reftree" => "self.treeid" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2012-09-05 10:57:15
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:3By30r0EiWTd8I1YBd2TjA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
