 package EPrints::Plugin::Screen::ChangesTab;
 
 @ISA = ( 'EPrints::Plugin::Screen' );
 
 use strict;
 use XML::SemanticDiff;
 # Make the plug-in
 
 sub new
 {
    my( $class, %params ) = @_;
 
    my $self = $class->SUPER::new(%params);
 
    # Where the button to access the screen appears if anywhere, and what priority
    $self->{appears} = [
       {
        #place => "eprint_actions",
		place => "eprint_editor_actions",
			position => 2650,
       },
    ];
 
    return $self;
 }
 
 # Only users with Editorial Review access can see this plugin
 sub can_be_viewed { 
	my( $self ) = @_;
	return $self->allow( "editorial_review" );
	#return $self->allow( "eprint/edit:editor" );
  }
 
 # What to display
 sub render
 {

    my( $self, $basename ) = @_;
 
    # Get the current repository object (so we can access the users, eprints information about things in this repository)
 
    my $repo = $self->repository;

	#my $eprint = $self->{processor}->{eprint};
	
	if (defined $repo) {

		my $eprint_id = $repo->param( "eprintid" );	

		my $eprint = $repo->eprint($eprint_id);

		if(defined $eprint){

			my @filters = (
				{ meta_fields => [qw( datasetid )], value => 'eprint', },
				{ meta_fields => [qw( objectid )], value => $eprint_id, },
			);


			my $list = $repo->dataset( "history" )->search(
				filters => \@filters,
				custom_order=>"-timestamp/-historyid",
			);
			
			
			return EPrints::Paginate->paginate_list(
				$repo,
				$basename,
			#	$basename."eprintid=".$eprint_id."&",
				$list,
				page_size => 10,
				params => {
					$self->{processor}->{screen}->hidden_bits,
					"eprintid"=>$eprint_id
				},
				container => $repo->make_element( "div" ),
				render_result => sub {
					my( undef, $item ) = @_;

					$item->set_parent( $eprint );
					return _render_history($item, $repo);
					#return $item->render;
				},
			);
		} # if(defined $eprint){	
	} # if (defined $eprint) {
	
 }
 
#############################################################################################################################
 
 sub _render_history
{
	my( $self, $repo ) = @_;

	my %pins = ();
	my $indexer = 0;
	
	my $user = $self->get_user;
	if( defined $user )
	{
		$pins{cause} = $user->render_description;
	}
	else
	{
		$pins{cause} = $self->{session}->make_element( "tt" );
		$pins{cause}->appendChild( $self->{session}->make_text( $self->get_value( "actor" ) ) );
		$indexer = 1 unless ($self->get_value( "actor" ) ne "indexer");
	}

	$pins{when} = $self->render_value( "timestamp" );
	my $action = $self->get_value( "action" );
	$pins{action} = $self->render_value( "action" );
	
	##
	my $obj  = $self->get_dataobj;
	if( defined $obj )
	{
		$pins{item} = $self->{session}->make_doc_fragment;
		$pins{item}->appendChild( $obj->render_description );
		$pins{item}->appendChild( $self->{session}->make_text( " (" ) );
 		my $a = $self->{session}->render_link( $obj->get_control_url );
		$pins{item}->appendChild( $a );
		$a->appendChild( $self->{session}->make_text( $self->get_value( "datasetid" )." ".$self->get_value("objectid" ) ) );
		$pins{item}->appendChild( $self->{session}->make_text( " r".$self->get_value( "revision" ) ) );
		$pins{item}->appendChild( $self->{session}->make_text( ")" ) );
	}
	else
	{
		$pins{item} = $self->{session}->html_phrase( 
			"lib/history:no_such_item", 
			datasetid=>$self->{session}->make_text($self->get_value( "datasetid" ) ),
			objectid=>$self->{session}->make_text($self->get_value( "objectid" ) ),
			 );
	}
	##
	
	if ($indexer)
	{
		$pins{details} = $self->{session}->make_text("");
		return $self->{session}->html_phrase( "lib/history:record", %pins );
	}
	##
	
	my $objectid = $self->get_value("objectid");
	my $revision = $self->get_value( "revision" );
	my $pre_revision = $revision-1;
	my $datasetid = $self->get_value("datasetid");
	if( ($datasetid eq "eprint") && ($objectid) )
	{
		my $path = _epid_to_path($objectid);
		my $cur_path = $repo->get_conf( "documents_path" )."/".$repo->get_store_dir."/" .$path."/revisions/".$revision.".xml";
		my $pre_path = $repo->get_conf( "documents_path" )."/".$repo->get_store_dir."/" .$path."/revisions/".$pre_revision.".xml";
		
		if ($revision == 1) {
			$pins{details} = $self->render;
		}
		else {
			#$pins{details} = $self->{session}->make_text( $cur_path );
			my $ul = $self->{session}->make_element("ul");
			
			my $render_history = Render_History->new();
			my $diff =  XML::SemanticDiff->new(diffhandler => $render_history,  keepdata => 1);
			my @results = $diff->compare( $pre_path, $cur_path );
			foreach my $result (@results) {
				my $li = $self->{session}->make_element("li");
				$li->appendChild( $self->{session}->make_text($result) );
				$ul->appendChild($li);
			}
			
			$pins{details} = $ul;
		}
	}
	##
	
	return $self->{session}->html_phrase( "lib/history:record", %pins );
}

sub _epid_to_path
{
	my( $id ) = @_;

	my $path = sprintf("%08d", $id);
	$path =~ s#(..)#/$1#g;
	substr($path,0,1) = '';

	return $path;
}


####################
package Render_History;

use EPrints;
use strict;

sub new
{
	my ($proto, %args) = @_;
	my $class = ref($proto) || $proto;
	my $self = \%args;
	bless ($self, $class);
	return $self;
}

sub rogue_element
{
	my ( $self, $name, $props ) = @_;
	return _print_debug($name, $props, "ADDED");
}

sub element_value
{
	my ( $self, $name, $props ) = @_;
	return _print_debug($name, $props, "MODIFIED");
}

sub missing_element
{
	my ( $self, $name, $props ) = @_;
	return _print_debug($name, $props, "REMOVED");
}
=comment
sub attribute_value
{
	my ( $self, $name, $props ) = @_;
	return _print_debug($name, $props, "");
}

sub namespace_uri
{
	my ( $self, $name, $props ) = @_;
	return _print_debug($name, $props, "");
}

sub rogue_attribute
{
	my ( $self, $name, $props ) = @_;
	return _print_debug($name, $props, "");
}

sub missing_attribute
{
	my ( $self, $name, $props ) = @_;
	return _print_debug($name, $props, "");
}
=cut
sub _print_debug
{
	my $name = shift;
	my $props = shift;
	my $action = shift;

	my $repo_id = 'library';
	my $ep = EPrints->new();
	my $repo = $ep->repository($repo_id, noise => 0);
	die "couldn't create repository for $repo_id\n" unless defined $repo;
	
	my @fields = ($name =~ m/\/([^\/]+)\[\d+\]/g);
	
	my $size = scalar @fields;
	
	my $object;
	my $field;
	
	if ($size >= 5 &&
		$fields[3] eq "files" &&
		$fields[4] eq "file") {
		$object = "file";
		$field = $fields[5] unless not defined $fields[5];
	}
	elsif ($size >= 3 &&
			$fields[1] eq "documents" &&
			$fields[2] eq "document") {
		$object = "document";
		$field = $fields[3] unless not defined $fields[3];
	}
	else {
		$object = "eprint";
		$field = $fields[1] unless not defined $fields[1];
	}
	
	my $dataset = $repo->dataset($object) unless not defined $object;
	
	if (defined $dataset && defined $field) {
		my $metafield = $dataset->field($field);
		my $phrasename = $metafield->{confid}."_fieldname_".$metafield->{name};
		my $meta_name = $repo->phrase($phrasename);
		my $value = $props->{CData};
		
		$repo->terminate();
		return "The $meta_name field is $action: $value." unless ( ($meta_name =~ /not defined\]$/) or ($value eq "o") );
	}
	
	$repo->terminate();
	return;
}

 
 
 
 
 1;