package MusicBrainz::Server::Controller::Recording;
use Moose;

BEGIN { extends 'MusicBrainz::Server::Controller'; }

with 'MusicBrainz::Server::Controller::Role::Annotation';
with 'MusicBrainz::Server::Controller::Role::Details';
with 'MusicBrainz::Server::Controller::Role::Relationship';
with 'MusicBrainz::Server::Controller::Role::Rating';
with 'MusicBrainz::Server::Controller::Role::Tag';
with 'MusicBrainz::Server::Controller::Role::EditListing';

__PACKAGE__->config(
    entity_name => 'recording',
    model       => 'Recording',
);

use MusicBrainz::Server::Constants qw(
    $EDIT_RECORDING_EDIT
    $EDIT_RECORDING_MERGE
    $EDIT_RECORDING_ADD_ISRCS
    $EDIT_PUID_DELETE
);

=head1 NAME

MusicBrainz::Server::Controller::Recording

=head1 DESCRIPTION

Handles user interaction with C<MusicBrainz::Server::Entity::Recording> entities.

=head1 METHODS

=head2 READ ONLY METHODS

=head2 base

Base action to specify that all actions live in the C<recording>
namespace

=cut

sub base : Chained('/') PathPart('recording') CaptureArgs(0) { }

after 'load' => sub
{
    my ($self, $c) = @_;

    my $recording = $c->stash->{recording};
    $c->model('Recording')->load_meta($recording);
    if ($c->user_exists) {
        $c->model('Recording')->rating->load_user_ratings($c->user->id, $recording);
    }
    my @isrcs = $c->model('ISRC')->find_by_recording($recording->id);
    $c->stash( isrcs => \@isrcs );
    $c->model('ArtistCredit')->load($recording);
};

after 'tags' => sub
{
    my ($self, $c) = @_;
    my $recording = $c->stash->{recording};
};

=head2 relations

Shows all relations to a given recording

=cut

sub relations : Chained('load')
{
    my ($self, $c, $mbid) = @_;
    $c->stash->{relations} = $c->model('Relation')->load_relations($self->entity);
}

=head2 details

Show details of a recording

=cut

after 'details' => sub
{
    my ($self, $c) = @_;
    # XXX Load PUID count?
    my $recording = $c->stash->{recording};
};

sub show : Chained('load') PathPart('')
{
    my ($self, $c) = @_;
    my $recording = $c->stash->{recording};
    my $tracks = $self->_load_paged($c, sub {
        $c->model('Track')->find_by_recording($recording->id, shift, shift);
    });
    my @releases = map { $_->tracklist->medium->release } @$tracks;
    $c->model('ArtistCredit')->load($recording, @$tracks, @releases);
    $c->model('Country')->load(@releases);
    $c->model('ReleaseLabel')->load(@releases);
    $c->model('Label')->load(map { $_->all_labels } @releases);
    $c->stash(
        tracks   => $tracks,
        template => 'recording/index.tt',
    );
}

sub puids : Chained('load') PathPart('puids')
{
    my ($self, $c) = @_;

    my $recording = $c->stash->{recording};
    my @puids = $c->model('RecordingPUID')->find_by_recording($recording->id);
    $c->stash(
        puids    => \@puids,
        template => 'recording/puids.tt',
    );
}

=head2 DESTRUCTIVE METHODS

This methods alter data

=head2 edit

Edit recording details (sequence number, recording time and title)

=cut

with 'MusicBrainz::Server::Controller::Role::Edit' => {
    form           => 'Recording',
    edit_type      => $EDIT_RECORDING_EDIT,
};

with 'MusicBrainz::Server::Controller::Role::Merge' => {
    edit_type => $EDIT_RECORDING_MERGE,
    search_template => 'recording/merge_search.tt',
    confirmation_template => 'recording/merge_confirm.tt'
};

before 'edit' => sub {
    my ($self, $c) = @_;
    my $recording = $c->stash->{recording};
};

after 'merge' => sub {
    my ($self, $c) = @_;
    $c->model('ArtistCredit')->load(
        $c->stash->{recording}, $c->stash->{old}, $c->stash->{new}
    );
};

around '_merge_search' => sub {
    my $orig = shift;
    my ($self, $c, $query) = @_;

    my $results = $self->$orig($c, $query);
    $c->model('ArtistCredit')->load(map { $_->entity } @$results);
    return $results;
};

sub add_isrc : Chained('load') PathPart('add-isrc') RequireAuth
{
    my ($self, $c) = @_;

    my $recording = $c->stash->{recording};
    my $form = $c->form(form => 'AddISRC');
    if ($c->form_posted && $form->submitted_and_valid($c->req->params)) {
        $self->_insert_edit(
            $c, $form,
            edit_type => $EDIT_RECORDING_ADD_ISRCS,
            isrcs => [ {
                isrc         => $form->field('isrc')->value,
                recording_id => $recording->id,
                source       => 0
            } ]
        );

        $c->response->redirect($c->uri_for_action('/recording/show', [ $recording->gid ]));
        $c->detach;
    }
}

sub delete_puid : Chained('load') PathPart('remove-puid') RequireAuth
{
    my ($self, $c) = @_;
    my $puid_str = $c->req->query_params->{puid};
    my $recording = $c->stash->{recording};
    my $puid = $c->model('RecordingPUID')->get_by_recording_puid($recording->id, $puid_str);

    if (!$puid) {
        $c->stash( message => 'Not a valid PUID' );
        $c->detach('/error_500');
    }
    else
    {
        $c->stash( puid => $puid );

        $self->edit_action($c,
            form => 'Confirm',
            type => $EDIT_PUID_DELETE,
            edit_args => {
                puid => $puid,
            },
            on_creation => sub {
                $c->response->redirect(
                    $c->uri_for_action('/recording/puids', [ $recording->gid ]));
            }
        );
    }
}

=head1 LICENSE

This software is provided "as is", without warranty of any kind, express or
implied, including  but not limited  to the warranties of  merchantability,
fitness for a particular purpose and noninfringement. In no event shall the
authors or  copyright  holders be  liable for any claim,  damages or  other
liability, whether  in an  action of  contract, tort  or otherwise, arising
from,  out of  or in  connection with  the software or  the  use  or  other
dealings in the software.

GPL - The GNU General Public License    http://www.gnu.org/licenses/gpl.txt
Permits anyone the right to use and modify the software without limitations
as long as proper  credits are given  and the original  and modified source
code are included. Requires  that the final product, software derivate from
the original  source or any  software  utilizing a GPL  component, such  as
this, is also licensed under the GPL license.

=cut

1;
