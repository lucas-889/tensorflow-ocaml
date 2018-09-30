(* Generative Adverserial Networks trained on the MNIST dataset. *)
open Base
open Tensorflow
open Tensorflow_core
module O = Ops

let image_dim = Mnist_helper.image_dim
let latent_dim = 100

let generator_hidden_nodes = 128
let discriminator_hidden_nodes = 128

let batch_size = 128
let learning_rate = 1e-5
let batches = 10**8

let create_generator rand_input =
  let linear1 = Layer.Linear.create generator_hidden_nodes in
  let linear2 = Layer.Linear.create image_dim in
  let output =
    Layer.Linear.apply linear1 rand_input ~activation:(Leaky_relu 0.01)
    |> Layer.Linear.apply linear2 ~activation:Tanh
  in
  output, (Layer.Linear.vars linear1 @ Layer.Linear.vars linear2)

let create_discriminator xs1 xs2 =
  let linear1 = Layer.Linear.create discriminator_hidden_nodes in
  let linear2 = Layer.Linear.create 1 in
  let model xs =
    Layer.Linear.apply linear1 xs ~activation:(Leaky_relu 0.01)
    |> Layer.Linear.apply linear2 ~activation:Sigmoid
  in
  let ys1 = model xs1 in
  let ys2 = model xs2 in
  ys1, ys2, (Layer.Linear.vars linear1 @ Layer.Linear.vars linear2)

let binary_cross_entropy ~label ~model_values =
  let epsilon = 1e-6 in
  O.(neg (f label * log (model_values + f epsilon)
    + f (1. -. label) * log (f (1. +. epsilon) - model_values)))
  |> O.reduce_mean

let () =
  let mnist = Mnist_helper.read_files () in
  let rand_data_ph = O.placeholder [batch_size; latent_dim] ~type_:Float in
  let real_data_ph = O.placeholder [batch_size; image_dim] ~type_:Float in
  let generated, gen_variables = create_generator (O.Placeholder.to_node rand_data_ph) in
  let real_doutput, fake_doutput, discriminator_variables =
    create_discriminator O.(Placeholder.to_node real_data_ph * f 2. - f 1.) generated
  in
  let real_loss = binary_cross_entropy ~label:0.9 ~model_values:real_doutput in
  let fake_loss = binary_cross_entropy ~label:0. ~model_values:fake_doutput in
  let discriminator_loss = O.(real_loss + fake_loss) in
  let generator_loss = binary_cross_entropy ~label:1. ~model_values:fake_doutput in
  let learning_rate = O.f learning_rate in
  let discriminator_opt =
    Optimizers.adam_minimizer ~learning_rate discriminator_loss
      ~varsf:discriminator_variables
  in
  let generator_opt =
    Optimizers.adam_minimizer ~learning_rate generator_loss ~varsf:gen_variables
  in
  let batch_rand = Tensor.create2 Float32 batch_size latent_dim in
  let samples_rand = Tensor.create2 Float32 batch_size latent_dim in
  Tensor.fill_uniform samples_rand ~lower_bound:(-1.) ~upper_bound:1.;
  for batch_idx = 1 to batches do
    let batch_images, _ = Mnist_helper.train_batch mnist ~batch_size ~batch_idx in
    let discriminator_loss =
      Tensor.fill_uniform batch_rand ~lower_bound:(-1.) ~upper_bound:1.;
      Session.run
        ~inputs:Session.Input.[
          float real_data_ph batch_images; float rand_data_ph batch_rand ]
        ~targets:discriminator_opt
        (Session.Output.scalar_float discriminator_loss)
    in
    let generator_loss =
      Tensor.fill_uniform batch_rand ~lower_bound:(-1.) ~upper_bound:1.;
      Session.run
        ~inputs:Session.Input.[ float rand_data_ph batch_rand ]
        ~targets:generator_opt
        (Session.Output.scalar_float generator_loss)
    in
    if batch_idx % 100 = 0
    then
      Stdio.printf "batch %4d    d-loss: %12.6f    g-loss: %12.6f\n%!"
        batch_idx discriminator_loss generator_loss;
    if batch_idx % 5000 = 0
    then begin
      let samples =
        Session.run (Session.Output.float generated)
          ~inputs:Session.Input.[ float rand_data_ph samples_rand ]
      in
      Stdio.Out_channel.with_file (Printf.sprintf "out%d.txt" batch_idx) ~f:(fun channel ->
        for sample_index = 0 to 15 do
          List.init image_dim ~f:(fun pixel_index ->
            Tensorflow_core.Tensor.get samples [|sample_index; pixel_index|]
            |> Printf.sprintf "%.2f")
          |> String.concat ~sep:", "
          |> Printf.sprintf "data%d = [%s]\n" sample_index
          |> Stdio.Out_channel.output_string channel
        done)
    end
  done