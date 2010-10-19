package MusicBrainz::Server::Controller::Role::Annotation;
use Moose::Role -traits => 'MooseX::MethodAttributes::Role::Meta::Role';

use MusicBrainz::Server::Constants qw( :annotation );
use MusicBrainz::Server::Data::Utils qw( model_to_type );
use MusicBrainz::Server::Translation qw( l ln );
use MusicBrainz::Server::Validation qw( is_positive_integer );

requires 'load', 'show';

my %model_to_edit_type = (
    Artist => $EDIT_ARTIST_ADD_ANNOTATION,
    Label => $EDIT_LABEL_ADD_ANNOTATION,
    Recording => $EDIT_RECORDING_ADD_ANNOTATION,
    Release => $EDIT_RELEASE_ADD_ANNOTATION,
    ReleaseGroup => $EDIT_RELEASEGROUP_ADD_ANNOTATION,
    Work => $EDIT_WORK_ADD_ANNOTATION,
);

sub latest_annotation : Chained('load') PathPart('annotation')
{
    my ($self, $c) = @_;

    my $entity = $c->stash->{entity};
    my $annotation = $c->model($self->{model})->annotation->get_latest($entity->id);

    $c->stash(
        annotation => $annotation,
        type       => model_to_type($self->{model}),
        template   => $self->action_namespace . '/annotation_revision.tt'
    );
}

sub annotation_revision : Chained('load') PathPart('annotation') Args(1)
{
    my ($self, $c, $id) = @_;

    my $entity = $c->stash->{entity};
    my $annotation = $c->model($self->{model})->annotation->get_by_id($id)
        or $c->detach('/error_404');

    $c->stash(
        annotation => $annotation,
        gid        => $entity->gid,
        type       => model_to_type($self->{model}),
    );
}

after 'show' => sub
{
    my ($self, $c) = @_;
    my $entity = $c->stash->{entity};
    my $type = $self->{model};

    $c->stash->{type} = model_to_type($type);
    $c->model($type)->annotation->load_latest($entity);
};

sub edit_annotation : Chained('load') PathPart RequireAuth Edit
{
    my ($self, $c) = @_;
    my $model = $self->{model};
    my $entity = $c->stash->{entity};
    my $annotation_model = $c->model($model)->annotation;
    $annotation_model->load_latest($entity);

    my $form = $c->form(
        form             => 'Annotation',
        init_object      => $entity->latest_annotation,
        annotation_model => $annotation_model,
        entity_id        => $entity->id
    );

    if ($c->form_posted && $form->submitted_and_valid($c->req->params))
    {
        if ($form->field('preview')->input) {
            $c->stash(
                show_preview => 1,
                preview      => $form->field('text')->value
            );
        }
        else
        {
            $self->_insert_edit(
                $c,
                $form,
                edit_type => $model_to_edit_type{$model},
                (map { $_->name => $_->value } $form->edit_fields),
                entity_id => $entity->id
            );

            my $show = $self->action_for('show');
            $c->response->redirect($c->uri_for_action($show, [ $entity->gid ]));
            $c->detach;
        }
    }
}

sub annotation_history : Chained('load') PathPart('annotations')
{
    my ($self, $c) = @_;

    my $model            = $self->{model};
    my $entity           = $c->stash->{entity};
    my $annotation_model = $c->model($model)->annotation;

    my $annotations = $self->_load_paged(
        $c, sub {
            $annotation_model->get_history($entity->id, @_);
        });

    $c->model('Editor')->load(@$annotations);
    $c->stash( annotations => $annotations );
}

sub annotation_diff : Chained('load') PathPart('annotations-differences')
{
    my ($self, $c) = @_;

    my $model            = $self->{model};
    my $entity           = $c->stash->{entity};
    my $annotation_model = $c->model($model)->annotation;

    my $old = $c->req->query_params->{old};
    my $new = $c->req->query_params->{new};

    unless (is_positive_integer($old) &&
            is_positive_integer($new) &&
            $old != $new) {
        $c->stash(
            message => l('The old and new annotation ids must be unique, positive integers.')
        );
        $c->detach('/error_400')
    }

    my $old_annotation = $annotation_model->get_by_id($old);
    my $new_annotation = $annotation_model->get_by_id($new);

    $c->stash(
        old => $old_annotation,
        new => $new_annotation
    );
}

no Moose::Role;
1;

